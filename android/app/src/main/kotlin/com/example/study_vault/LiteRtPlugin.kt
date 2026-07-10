// LiteRtPlugin.kt
package com.example.study_vault

import android.content.Context
import android.widget.Toast
import com.google.ai.edge.litertlm.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.catch
import io.flutter.plugin.common.EventChannel

class LiteRtPlugin(private val context: Context) {
    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var generationJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // نخزن موجّه النظام لإعادة استخدامه عند إنشاء محادثة جديدة لكل طلب
    // السبب: المحادثة الأصلية كانت تُعادَ استخدامها فيطول سياقها → يقطع النموذج
    // بعد توكنَين فقط (ظهور "**" في ردّ الطلب الثاني بعد ردّ طويل سابق).
    private var savedSystemPrompt: String? = null

    // 🔥 دالة التطهير العميقة لمحاكاة إعادة تشغيل التطبيق وتفريغ الموارد الأصلية
    private suspend fun forceResetNativeResources() {
        withContext(Dispatchers.IO) {
            try {
                generationJob?.cancelAndJoin()
            } catch (e: Exception) { }
            generationJob = null

            try {
                conversation?.close()
            } catch (e: Exception) { }
            conversation = null

            try {
                engine?.close()
            } catch (e: Exception) { }
            engine = null

            // ⚠️ استدعاء تفريغ الذاكرة العشوائية لطبقة C++ والـ Java
            System.gc()
            Runtime.getRuntime().gc()

            // ⏱️ تأخير زمني بمقدار 400 ملي ثانية للسماح لتعريفات العتاد بتحرير الأقفال
            delay(400)
        }
    }

    suspend fun initializeEngine(
        modelPath: String,
        backend: String,
        systemPrompt: String? = null,
        maxTokens: Int = 256,
        temperature: Float = 0.6f,
        topK: Int = 30,
        supportVision: Boolean = false // ✅ المعامل الجديد
    ) {
        // تنظيف وتفريغ شامل قبل البدء لضمان بيئة عذراء
        forceResetNativeResources()

        withContext(Dispatchers.IO) {
            // ✅ تجهيز قائمة بالمعالجات التي سيتم تجربتها بالترتيب (آلية الرجوع التلقائي)
            val backendsToTry = mutableListOf<Backend>()
            when (backend.lowercase()) {
                "npu" -> {
                    backendsToTry.add(Backend.NPU(nativeLibraryDir = context.applicationInfo.nativeLibraryDir))
                    backendsToTry.add(Backend.GPU()) // الرجوع الأول
                    backendsToTry.add(Backend.CPU()) // الملاذ الأخير
                }
                "gpu" -> {
                    backendsToTry.add(Backend.GPU())
                    backendsToTry.add(Backend.CPU())
                }
                else -> {
                    backendsToTry.add(Backend.CPU())
                }
            }

            var isInitialized = false
            var lastExceptionMessage = ""
            var visionToastShown = false

            for (currentBackend in backendsToTry) {
                if (isInitialized) break

                val backendName = currentBackend.javaClass.simpleName
                android.util.Log.d("LiteRtPlugin", "🔄 جاري محاولة التهيئة باستخدام معالج: $backendName")

                // 1️⃣ الخطوة الأولى: إذا اختار المستخدم دعم الصور، نحاول تهيئته على المعالج الحالي
                if (supportVision && !isInitialized) {
                    try {
                        android.util.Log.d("LiteRtPlugin", "🔄 جاري محاولة تهيئة النموذج مع مسرع الصور (Vision) على $backendName...")
                        val configWithVision = EngineConfig(
                            modelPath = modelPath,
                            backend = currentBackend,
                            visionBackend = if (currentBackend is Backend.CPU) null else Backend.GPU(),
                            cacheDir = context.cacheDir.path
                        )
                        val testEngine = Engine(configWithVision)
                        testEngine.initialize()
                        engine = testEngine
                        isInitialized = true

                        // احفظ موجّه النظام لاستخدامه عند كل طلب
                        savedSystemPrompt = if (systemPrompt.isNullOrEmpty()) null else systemPrompt
                        createNewConversation(savedSystemPrompt)
                        android.util.Log.d("LiteRtPlugin", "✅ نجحت التهيئة مع دعم الصور على معالج $backendName!")
                    } catch (e: Exception) {
                        android.util.Log.w("LiteRtPlugin", "⚠️ فشل دعم الصور على معالج $backendName. جاري التطهير والتحويل التلقائي لوضع النصوص...")
                        lastExceptionMessage = e.message ?: "فشل محرك الصور"

                        if (!visionToastShown) {
                            withContext(Dispatchers.Main) {
                                Toast.makeText(
                                    context,
                                    "⚠️ هذا النموذج أو المعالج لا يدعم الصور! تم التحويل تلقائياً لوضع النصوص.",
                                    Toast.LENGTH_LONG
                                ).show()
                            }
                            visionToastShown = true
                        }
                        // ⚡ تفريغ الموارد الملوثة فوراً لإزالة الأقفال التالفة قبل المحاولة التالية
                        forceResetNativeResources()
                    }
                }

                // 2️⃣ الخطوة الثانية (Fallback): في حال لم يتم اختيار دعم الصور أو فشلت المحاولة الأولى
                if (!isInitialized) {
                    try {
                        android.util.Log.d("LiteRtPlugin", "🔄 جاري تهيئة النموذج في وضع النصوص فقط (Text-Only) على $backendName...")
                        val configWithoutVision = EngineConfig(
                            modelPath = modelPath,
                            backend = currentBackend,
                            visionBackend = null, // تعطيل محرك الصور نهائياً
                            cacheDir = context.cacheDir.path
                        )
                        val testEngine = Engine(configWithoutVision)
                        testEngine.initialize()
                        engine = testEngine
                        isInitialized = true

                        // احفظ موجّه النظام لاستخدامه عند كل طلب
                        savedSystemPrompt = if (systemPrompt.isNullOrEmpty()) null else systemPrompt
                        createNewConversation(savedSystemPrompt)
                        android.util.Log.d("LiteRtPlugin", "✅ تم تهيئة النموذج بنجاح كوضع نصوص فقط على معالج $backendName")

                        if (supportVision && !visionToastShown) {
                            withContext(Dispatchers.Main) {
                                Toast.makeText(
                                    context,
                                    "⚠️ هذا النموذج لا يدعم الصور! تم تحويله تلقائياً لوضع النصوص.",
                                    Toast.LENGTH_LONG
                                ).show()
                            }
                            visionToastShown = true
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("LiteRtPlugin", "❌ فشلت التهيئة على معالج $backendName: ${e.message}")
                        lastExceptionMessage = e.message ?: "خطأ غير معروف في المعالج"
                        // تنظيف قبل تجربة المعالج التالي في القائمة
                        forceResetNativeResources()
                    }
                }
            }

            // إذا انتهت الحلقة ولم ينجح أي معالج
            if (!isInitialized) {
                android.util.Log.e("LiteRtPlugin", "❌ فشلت جميع محاولات التهيئة النهائية.")
                throw Exception("تعذرت تهيئة النموذج. التفاصيل الفنية: $lastExceptionMessage")
            }
        }
    }

    private fun createNewConversation(systemPrompt: String? = null) {
        val currentEngine = engine ?: return
        val conversationConfig = ConversationConfig(
            systemInstruction = if (!systemPrompt.isNullOrEmpty()) Contents.of(systemPrompt) else null
        )
        conversation = currentEngine.createConversation(conversationConfig)
    }

    suspend fun startGeneration(prompt: String, imagePath: String?, events: EventChannel.EventSink) {
        // 1) إلغاء الجيل السابق وانتظار اكتماله فعلاً قبل أي شيء
        try {
            generationJob?.cancelAndJoin()
        } catch (e: Exception) { }
        generationJob = null

        // 2) إنشاء محادثة جديدة كلياً لكل طلب — يحل تكرار السياق الذي كان يقطع
        //    ردود النموذج بعد رسالة طويلة (ظهور "**" فقط في الردّ الثاني).
        try {
            createNewConversation(savedSystemPrompt)
        } catch (e: Exception) {
            android.util.Log.w("LiteRtPlugin", "⚠️ تعذّر إنشاء محادثة جديدة، سأستخدم القديمة: ${e.message}")
        }

        // 3) تشغيل الجيل الجديد
        generationJob = scope.launch {
            try {
                if (!isActive) return@launch

                val contentsList = mutableListOf<Content>()

                if (!imagePath.isNullOrEmpty()) {
                    contentsList.add(Content.ImageFile(imagePath))
                }

                if (prompt.isNotEmpty()) {
                    contentsList.add(Content.Text(prompt))
                }

                val message = if (contentsList.size == 1 && contentsList.first() is Content.Text) {
                    Message.of(prompt)
                } else {
                    Message.user(Contents.of(contentsList))
                }

                val responseFlow = conversation?.sendMessageAsync(message)
                    ?: throw IllegalStateException("Conversation is null")

                responseFlow.catch { e ->
                    if (isActive) {
                        withContext(Dispatchers.Main) {
                            events.error("GEN_ERR", e.message ?: "Unknown generation error", null)
                        }
                    }
                }.collect { responseMessage ->
                    if (!isActive) {
                        throw CancellationException("User stopped generation")
                    }

                    val text = responseMessage.contents.contents
                        .filterIsInstance<Content.Text>()
                        .joinToString("") { it.text }

                    if (text.isNotEmpty()) {
                        withContext(Dispatchers.Main) {
                            events.success(text)
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    events.endOfStream()
                }
            } catch (e: CancellationException) {
                withContext(Dispatchers.Main) {
                    events.endOfStream()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    events.error("GEN_ERR", e.message ?: "Unknown error", null)
                }
            }
        }
    }

    fun stopGeneration() {
        generationJob?.cancel()
        generationJob = null
    }

    suspend fun close() {
        forceResetNativeResources()
    }
}

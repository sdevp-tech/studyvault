import 'dart:io';
import 'package:path/path.dart' as p;

/// Central resolver that converts between absolute on-disk paths and
/// storage-stable RELATIVE paths.
///
/// OFFLINE-FIRST BUG FIXED:
/// The application documents directory can change across OS updates and
/// reinstalls (most notably the iOS container UUID). Persisting ABSOLUTE paths
/// in Hive meant that after such a change every asset "vanished" even though
/// the files were still on disk. We now persist paths that are stable relative
/// to a known vault anchor ("StudyVault") and resolve them to an absolute path
/// against the CURRENT app-documents root at read time.
class PathResolver {
  PathResolver._();

  static String? _appDocRoot;

  /// Must be called exactly once at startup (before any asset path is resolved).
  static void init(String appDocumentsDirPath) {
    _appDocRoot = appDocumentsDirPath;
  }

  static bool get isInitialized => _appDocRoot != null;

  static String get appDocRoot {
    final root = _appDocRoot;
    if (root == null) {
      throw StateError(
          'PathResolver.init() must be called before resolving paths.');
    }
    return root;
  }

  /// Converts a stored path (relative, or a legacy absolute path) into an
  /// absolute path anchored to the CURRENT app-documents root.
  static String resolve(String stored) {
    if (stored.isEmpty) return stored;

    // Already relative → simply join with the current root.
    if (!p.isAbsolute(stored)) {
      return p.join(appDocRoot, stored);
    }

    // Legacy absolute path → re-anchor it so it survives container changes.
    final rel = _relativeToVault(stored);
    if (rel != null) {
      return p.join(appDocRoot, rel);
    }

    // Unknown absolute path (e.g. a temp file outside the vault) → untouched.
    return stored;
  }

  /// Converts an absolute path into a storage-stable value before persisting.
  static String toStorable(String absolutePath) {
    if (absolutePath.isEmpty) return absolutePath;
    if (!p.isAbsolute(absolutePath)) return absolutePath; // already relative

    final rel = _relativeToVault(absolutePath);
    if (rel != null) return rel;

    // Under the current root but not under a "StudyVault" segment → relativize.
    if (PathResolver.isInitialized && p.isWithin(appDocRoot, absolutePath)) {
      return p.relative(absolutePath, from: appDocRoot);
    }

    // Outside the vault entirely → keep as-is.
    return absolutePath;
  }

  /// Returns true when [stored] resolves to a file that exists on disk.
  static bool existsSync(String stored) {
    try {
      return File(resolve(stored)).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Extracts a path starting at the well-known "StudyVault" anchor segment.
  static String? _relativeToVault(String absolutePath) {
    final normalized = p.normalize(absolutePath).replaceAll('\\', '/');
    final segments = p.split(normalized);
    final idx = segments.lastIndexOf('StudyVault');
    if (idx >= 0) {
      return p.joinAll(segments.sublist(idx));
    }
    return null;
  }
}

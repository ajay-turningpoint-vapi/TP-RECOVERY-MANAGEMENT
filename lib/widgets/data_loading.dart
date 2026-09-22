import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';

const _blue = Color(0xFF2563EB);

/// A slim indeterminate bar shown whenever the app is fetching the core
/// lists from the server — login / session restore, a bottom-nav tab
/// switch, or an SSE-triggered re-fetch. Place it at the top of a scaffold
/// body so a background load is never completely invisible.
class DataLoadingBar extends StatelessWidget {
  const DataLoadingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AppStore, bool>((s) => s.isFetchingData);
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      child: busy
          ? const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Color(0x142563EB),
              valueColor: AlwaysStoppedAnimation(_blue),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}

/// Drop-in `AppBar.bottom` that shows the same thin fetch-in-progress bar
/// under a screen's app bar. Zero height (invisible) when idle, so it can
/// stay wired permanently:
///   appBar: AppBar(..., bottom: const LoadingAppBarStrip()),
class LoadingAppBarStrip extends StatelessWidget implements PreferredSizeWidget {
  /// Bar colour — white reads well on a coloured app bar (the default);
  /// pass the accent blue for a white app bar.
  final Color color;
  const LoadingAppBarStrip({super.key, this.color = Colors.white});

  @override
  Size get preferredSize => const Size.fromHeight(3);

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AppStore, bool>((s) => s.isFetchingData);
    return SizedBox(
      height: 3,
      child: busy
          ? LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation(color),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Full-area loader for the window between the scaffold rendering and the
/// first server fetch completing (real on a warm start — see
/// AppStore.restoreSession, which shows the UI before data arrives). Once
/// `hasLoadedInitialData` flips (including from a local cache — see
/// AppStore._loadFromCache), [child] is shown as normal. Only a genuinely
/// cache-less first-ever load with no connectivity can still land here —
/// bounded by _refreshAllFromApi's own timeout, and shown with a real
/// retry button rather than spinning forever (see AppStore.initialLoadError
/// / retryInitialLoad).
class InitialDataLoader extends StatelessWidget {
  final Widget child;
  const InitialDataLoader({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final loading = context.select<AppStore, bool>((s) => s.isInitialDataLoading);
    if (!loading) return child;
    final error = context.select<AppStore, String?>((s) => s.initialLoadError);
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFF94A3B8)),
              const SizedBox(height: 14),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              LoadingElevatedButton(
                onPressed: () async => context.read<AppStore>().retryInitialLoad(),
                style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(_blue)),
          ),
          SizedBox(height: 14),
          Text('Loading your data…',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

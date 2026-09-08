import 'package:flutter/material.dart';

/// This app is designed mobile-only. On a wide browser window (desktop),
/// clamp the rendered app to a phone-sized viewport instead of letting
/// every screen stretch full-width — matches the intended phone layout
/// regardless of how large the browser window is.
const double kMobileFrameWidth = 430;

/// The narrowest logical width the screens are laid out for. The dense
/// dashboard rows (stat strips, table headers, button pairs) are tuned for
/// a ~360px phone and start to overflow below this. Rather than fixing 600+
/// individual Rows, when the real viewport is narrower than this we lay the
/// app out AT this width and uniformly scale the whole UI down to fit the
/// actual space — no horizontal overflow, proportions preserved.
const double kMinLayoutWidth = 340;

class MobileFrame extends StatelessWidget {
  final Widget child;
  const MobileFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // --- Narrower than the design minimum: scale-to-fit ---------------
        // Very small phones, split-screen / multi-window, or a desktop
        // window dragged narrower than the phone frame. Render at
        // kMinLayoutWidth and shrink so every screen still fits.
        if (maxWidth.isFinite && maxWidth < kMinLayoutWidth) {
          final scale = maxWidth / kMinLayoutWidth;
          final outerHeight =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 932.0;
          final logicalHeight = outerHeight / scale;
          final mq = MediaQuery.of(context);
          return MediaQuery(
            // The app now believes it has a kMinLayoutWidth-wide viewport;
            // the visual scale-down is applied below by the FittedBox. Inset
            // padding is divided by the scale so it still lands in the right
            // physical place after scaling.
            data: mq.copyWith(
              size: Size(kMinLayoutWidth, logicalHeight),
              padding: mq.padding * (1 / scale),
              viewPadding: mq.viewPadding * (1 / scale),
              viewInsets: mq.viewInsets * (1 / scale),
            ),
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: kMinLayoutWidth,
                height: logicalHeight,
                child: child,
              ),
            ),
          );
        }

        // --- Phone-sized (or narrower, but >= min): render as-is ----------
        if (maxWidth <= kMobileFrameWidth) {
          return child;
        }

        // --- Wide window: clamp to a centered phone-sized frame -----------
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 932.0;
        return ColoredBox(
          color: const Color(0xFF0F172A),
          child: Center(
            child: SizedBox(
              width: kMobileFrameWidth,
              height: height,
              child: Material(
                elevation: 16,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.zero,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(size: Size(kMobileFrameWidth, height)),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

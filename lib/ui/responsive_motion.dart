import 'package:flutter/material.dart';

/// Open working screens immediately; keep focus/selection feedback visible.
class ImmediatePageTransitionsBuilder extends PageTransitionsBuilder {
  const ImmediatePageTransitionsBuilder();
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

import 'engine.dart';

/// One jump per touch; continued horizontal motion renews steering.
class SwipeInput {
  double originX = 0, originY = 0, lastX = 0;
  bool jumped = false, active = false;
  void begin(double x, double y) {
    originX = lastX = x;
    originY = y;
    jumped = false;
    active = true;
  }

  Swipe? update(double x, double y) {
    if (!active) return null;
    final dx = x - originX, dy = y - originY, travel = x - lastX;
    if (!jumped && dy < -16) {
      jumped = true;
      lastX = x;
      return dx.abs() > 12 ? (dx < 0 ? Swipe.upLeft : Swipe.upRight) : Swipe.up;
    }
    if (travel.abs() >= 4 && dx.abs() >= 10) {
      lastX = x;
      return travel < 0 ? Swipe.left : Swipe.right;
    }
    return null;
  }

  void end() {
    active = false;
  }
}

#pragma once

#include <GLKit/GLKMath.h>



/// Just GLKVector2Length() with the sqrt() operation removed.
static inline float GLKVector2LengthSqr(GLKVector2 vector);

/// Just GLKVector2Distance() with the sqrt() operation removed.
static inline float GLKVector2DistanceSqr(GLKVector2 vectorStart, GLKVector2 vectorEnd);

/// Simply rearranges the values (and inverts one) and plugs them into GLKVector2DotProduct.
static inline float GLKVector2CrossProduct(GLKVector2 vectorLeft, GLKVector2 vectorRight);

/// Returns a vector perpendicular to the given vector, rotate 90° counter-clockwise.
static inline GLKVector2 GLKVector2Perp(GLKVector2 vector);



#include "GLKMathExtensions.inl"

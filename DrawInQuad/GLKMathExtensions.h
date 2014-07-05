#pragma once

#include <GLKit/GLKMath.h>



static const GLKVector2 GLKVector2Invalid = { .x = NAN, .y = NAN };

static inline bool GLKVector2IsInvalid(GLKVector2 vector);

/// Just GLKVector2Length() with the sqrt() operation removed.
static inline float GLKVector2LengthSqr(GLKVector2 vector);

/// Just GLKVector2Distance() with the sqrt() operation removed.
static inline float GLKVector2DistanceSqr(GLKVector2 vectorStart, GLKVector2 vectorEnd);

/// Simply rearranges the values (and inverts one) and plugs them into GLKVector2DotProduct.
static inline float GLKVector2CrossProduct(GLKVector2 vectorLeft, GLKVector2 vectorRight);

/// Returns a vector perpendicular to the given vector, rotate 90° counter-clockwise.
static inline GLKVector2 GLKVector2Perp(GLKVector2 vector);

/// Adds 'em together and divides by the number of 'em.
static inline GLKVector2 GLKVector2Avg2(GLKVector2 vectorA, GLKVector2 vectorB);
static inline GLKVector2 GLKVector2Avg3(GLKVector2 vectorA, GLKVector2 vectorB, GLKVector2 vectorC);
static inline GLKVector2 GLKVector2Avg4(GLKVector2 vectorA, GLKVector2 vectorB, GLKVector2 vectorC, GLKVector2 vectorD);

/// Angle in radians; X+ is 0° increasing counter-clockwise until 180° (PI), then -180° back to 0°.
static inline float GLKVector2Angle(GLKVector2 vector);

/// Slerp (angle and magnitude-lerp) for GLKVector2
static inline GLKVector2 GLKVector2Slerp(GLKVector2 vectorStart, GLKVector2 vectorEnd, float t);



#include "GLKMathExtensions.inl"

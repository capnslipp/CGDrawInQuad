#if defined(__ARM_NEON__)
	#include <arm_neon.h>
#endif



static inline float GLKVector2LengthSqr(GLKVector2 vector)
{
	#if defined(__ARM_NEON__)
		float32x2_t v = vmul_f32(
			*(float32x2_t *)&vector,
			*(float32x2_t *)&vector
		);
		v = vpadd_f32(v, v);
		return vget_lane_f32(v, 0);
	#else
		return vector.v[0] * vector.v[0] + vector.v[1] * vector.v[1];
	#endif
}

static inline float GLKVector2DistanceSqr(GLKVector2 vectorStart, GLKVector2 vectorEnd)
{
	return GLKVector2LengthSqr(GLKVector2Subtract(vectorEnd, vectorStart));
}

/// A hand-written NEON-accelerated version would be ideal, unfortunately my attempts have bee not-so-successful.
static inline float GLKVector2CrossProduct(GLKVector2 vectorLeft, GLKVector2 vectorRight)
{
	return GLKVector2DotProduct(
		GLKVector2Make(vectorLeft.x, -vectorLeft.y),
		GLKVector2Make(vectorRight.y, vectorRight.x)
	);
}

/// Devised by F. S. Hill Jr. in Graphics Gems IV (1994).
///		@source: http://mathworld.wolfram.com/PerpendicularVector.html
static inline GLKVector2 GLKVector2Perp(GLKVector2 vector)
{
	return GLKVector2Make(-vector.y, vector.x);
}

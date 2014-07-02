#pragma once

#include <CoreFoundation/CFData.h>
#include <GLKit/GLKVector2.h>



typedef enum OutsideOfQuadUVMode
{
	OutsideOfQuadUVWrap,
	OutsideOfQuadUVClamp,
	OutsideOfQuadUVSkip,
} OutsideOfQuadUVMode;


#ifdef __cplusplus
	/// @arg points: Specified in standard OpenGL quad/quadstrip order: back-right, back-left, front-right, front-left
	template<OutsideOfQuadUVMode tUVMode, int tComponentCount>
	CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4]);
#endif


#ifdef __cplusplus
	extern "C" {
#endif

CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4], OutsideOfQuadUVMode uvMode, int channelCount);

#ifdef __cplusplus
	} // extern "C"
#endif

#pragma once

#include <CoreFoundation/CFData.h>
#include <GLKit/GLKVector2.h>



typedef enum OutsideOfQuadUVMode
{
	OutsideOfQuadUVWrap,
	OutsideOfQuadUVClamp,
	OutsideOfQuadUVSkip,
} OutsideOfQuadUVMode;


CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4], OutsideOfQuadUVMode uvMode);

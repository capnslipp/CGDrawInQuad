#pragma once

#include <CoreFoundation/CFData.h>
#include <CoreGraphics/CGGeometry.h>



typedef enum OutsideOfQuadUVMode
{
	OutsideOfQuadUVWrap,
	OutsideOfQuadUVClamp,
	OutsideOfQuadUVSkip,
} OutsideOfQuadUVMode;


UInt8 * createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, CGPoint points[4], OutsideOfQuadUVMode uvMode, size_t *out_byteCount);

#pragma once

#include <CoreFoundation/CFData.h>
#include <CoreGraphics/CGGeometry.h>



UInt8 * createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, CGPoint points[4], bool wrapUVs, size_t *out_byteCount);

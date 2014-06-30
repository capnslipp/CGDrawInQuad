#include "CGTextureMapping.h"

#include <stdbool.h>
#include <assert.h>

#include "GLKMathExtensions.h"



#pragma mark Intermediate Data

struct DestImageGenInfo {
	int srcWidth_i, srcHeight_i;
	float srcWidth_f, srcHeight_f;
	const UInt8 * srcBytes;
	
	int destWidth, destHeight;
	
	union {
		GLKVector2 points[4];
		struct { GLKVector2 point1, point2, point3, point4; };
	};
};



#pragma mark Util Functions

static inline int modulo(int dividendA, int divisorN)
{
	if (divisorN < 0) // you can check for divisorN == 0 separately and do what you want
		return modulo(-dividendA, -divisorN);
	
	int ret = dividendA % divisorN;
	if (ret < 0)
		ret += divisorN;
	
	return ret;
}

static inline int clampi(int v, int l, int h)
{
	if (v < l)
		return l;
	else if (v > h)
		return h;
	else
		return v;
}

static inline bool withini(int v, int l, int h)
{
	return v >= l && v <= h;
}

static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 *out_nearestPoint)
{
	GLKVector2 segmentDelta = GLKVector2Subtract(segmentBPoint, segmentAPoint);
	GLKVector2 freeToADelta = GLKVector2Subtract(freePoint, segmentAPoint);
	
	float ratioAlongSegment = GLKVector2DotProduct(freeToADelta, segmentDelta) / GLKVector2LengthSqr(segmentDelta);
	
	if (out_nearestPoint != NULL) {
		if (ratioAlongSegment <= 0.0f)
			*out_nearestPoint = segmentAPoint;
		else if (ratioAlongSegment >= 1.0f)
			*out_nearestPoint = segmentBPoint;
		else
			*out_nearestPoint = GLKVector2Add(segmentAPoint, GLKVector2MultiplyScalar(segmentDelta, ratioAlongSegment));
	}
	
	return ratioAlongSegment;
}

/// @source: Real-Time Collision Detection by Christer Ericson (Morgan Kaufmann, 2005) - Chapter 3: A Math and Geometry Primer - Section 3.4 Barycentric Coordinates
static inline GLKVector3 barycentricCoords2(const GLKVector2 point, const GLKVector2 tri[3])
{
	GLKVector2 v0 = GLKVector2Subtract(tri[1], tri[0]),
		v1 = GLKVector2Subtract(tri[2], tri[0]),
		v2 = GLKVector2Subtract(point, tri[0]);
	
	float d00 = GLKVector2DotProduct(v0, v0),
		d01 = GLKVector2DotProduct(v0, v1),
		d11 = GLKVector2DotProduct(v1, v1),
		d20 = GLKVector2DotProduct(v2, v0),
		d21 = GLKVector2DotProduct(v2, v1);
	
	float denomReciprocal = 1.0f / (d00 * d11 - d01 * d01);
	float v = (d11 * d20 - d01 * d21) * denomReciprocal;
	float w = (d00 * d21 - d01 * d20) * denomReciprocal;
	
	return GLKVector3Make(1.0f - v - w, v, w);
}


#pragma mark Texture Mapping Functions

/// Based on a loose understanding of Wikipedia's article on Bilinear interpolation (https://en.wikipedia.org/wiki/Bilinear_interpolation).
/// 	Probably not the best algoritm for this— works, but with more distortion as the points become less square.
/// 	Seems to show better results when the left and right sides of the points quad are parallel.
GLKVector2 surfaceSTToTexelUV_bilinearQuad(const GLKVector2 surfaceST, const GLKVector2 pointSTs[4], const GLKVector2 pointUVs[4])
{
	GLKVector2 nearestPointOn03Segment, nearestPointOn12Segment;
	float ratioAlong03 = ratioAlongSegment(surfaceST, pointSTs[0], pointSTs[3], &nearestPointOn03Segment);
	float ratioAlong12 = ratioAlongSegment(surfaceST, pointSTs[1], pointSTs[2], &nearestPointOn12Segment);
	
	GLKVector2 nearestPointOn03SegmentUV = GLKVector2Lerp(pointUVs[0], pointUVs[3], ratioAlong03);
	GLKVector2 nearestPointOn12SegmentUV = GLKVector2Lerp(pointUVs[1], pointUVs[2], ratioAlong12);
	
	float ratioBetweenNearest03And12 = ratioAlongSegment(surfaceST, nearestPointOn03Segment, nearestPointOn12Segment, NULL);
	
	GLKVector2 texelUV = GLKVector2Lerp(nearestPointOn03SegmentUV, nearestPointOn12SegmentUV, ratioBetweenNearest03And12);
	return texelUV;
}

GLKVector2 surfaceSTToTexelUV_barycentricTri(const GLKVector2 surfaceST, const GLKVector2 pointSTs[3], const GLKVector2 pointUVs[3])
{
	GLKVector3 barycentricCoords = barycentricCoords2(surfaceST, pointSTs);
	
	GLKVector2 pointUVsPortioned[3] = {
		GLKVector2MultiplyScalar(pointUVs[0], barycentricCoords.v[0]),
		GLKVector2MultiplyScalar(pointUVs[1], barycentricCoords.v[1]),
		GLKVector2MultiplyScalar(pointUVs[2], barycentricCoords.v[2])
	};
	
	GLKVector2 texelUV = GLKVector2Add(GLKVector2Add(pointUVsPortioned[0], pointUVsPortioned[1]), pointUVsPortioned[2]);
	return texelUV;
}

GLKVector2 surfaceSTToTexelUV_barycentricQuad(const GLKVector2 surfaceST, const GLKVector2 pointSTs[4], const GLKVector2 pointUVs[4])
{
	static const int kStarboardTriInQuadIndices[3] = { 0, 1, 2 };
	static const int kPortTriInQuadIndices[3] = { 0, 2, 3 };
	
	//// @source http://stackoverflow.com/questions/1560492/how-to-tell-whether-a-point-is-to-the-right-or-left-side-of-a-line
	float lineVsPointCross = GLKVector2CrossProduct(
		GLKVector2Subtract(pointSTs[2], pointSTs[0]),
		GLKVector2Subtract(surfaceST, pointSTs[0])
	);
	bool starboardSide = lineVsPointCross > 0.0f;
	
	const int *triInQuadIndices = starboardSide ? kStarboardTriInQuadIndices : kPortTriInQuadIndices;
	return surfaceSTToTexelUV_barycentricTri(
		surfaceST,
		(GLKVector2[3]){
			pointSTs[triInQuadIndices[0]],
			pointSTs[triInQuadIndices[1]],
			pointSTs[triInQuadIndices[2]]
		},
		(GLKVector2[3]){
			pointUVs[triInQuadIndices[0]],
			pointUVs[triInQuadIndices[1]],
			pointUVs[triInQuadIndices[2]]
		}
	);
}

template<OutsideOfQuadUVMode tUVMode> bool normalizeTexelXY(int *x, int *y, int srcWidth, int srcHeight);
template<> inline bool normalizeTexelXY<OutsideOfQuadUVWrap>(int *x, int *y, int srcWidth, int srcHeight)
{
	if (!withini(*x, 0, srcWidth - 1))
		*x = modulo(*x, srcWidth);
	if (!withini(*y, 0, srcHeight - 1))
		*y = modulo(*y, srcHeight);
	
	return true;
}
template<> inline bool normalizeTexelXY<OutsideOfQuadUVClamp>(int *x, int *y, int srcWidth, int srcHeight)
{
	if (!withini(*x, 0, srcWidth - 1))
		*x = clampi(*x, 0, srcWidth - 1);
	if (!withini(*y, 0, srcHeight - 1))
		*y = clampi(*y, 0, srcHeight - 1);
	
	return true;
}
template<> inline bool normalizeTexelXY<OutsideOfQuadUVSkip>(int *x, int *y, int srcWidth, int srcHeight)
{
	if (!withini(*x, 0, srcWidth - 1))
		return false;
	if (!withini(*y, 0, srcHeight - 1))
		return false;
	
	return true;
}

template<int tComponentCount> void copyBytesToPixelFromTexel(UInt8 *texelBytes, const UInt8 *pixelBytes);
template<> inline void copyBytesToPixelFromTexel<1>(UInt8 *pixelBytes, const UInt8 *texelBytes)
{
	pixelBytes[0] = texelBytes[0];
}
template<> inline void copyBytesToPixelFromTexel<2>(UInt8 *pixelBytes, const UInt8 *texelBytes)
{
	pixelBytes[0] = texelBytes[0];
	pixelBytes[1] = texelBytes[1];
}
template<> inline void copyBytesToPixelFromTexel<3>(UInt8 *pixelBytes, const UInt8 *texelBytes)
{
	pixelBytes[0] = texelBytes[0];
	pixelBytes[1] = texelBytes[1];
	pixelBytes[2] = texelBytes[2];
}
template<> inline void copyBytesToPixelFromTexel<4>(UInt8 *pixelBytes, const UInt8 *texelBytes)
{
	pixelBytes[0] = texelBytes[0];
	pixelBytes[1] = texelBytes[1];
	pixelBytes[2] = texelBytes[2];
	pixelBytes[3] = texelBytes[3];
}

template<OutsideOfQuadUVMode tUVMode, int tComponentCount>
void genDestImagePixelBytes(const struct DestImageGenInfo *info, const int pixelX, const int pixelY, UInt8 *pixelByteBuffer)
{
	static const int kBytesPerPixel = tComponentCount;
	
	static const GLKVector2 kPointUVs[4] = {
		(GLKVector2){ .x = 0.0f, .y = 0.0f },
		(GLKVector2){ .x = 0.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 0.0f },
	};
	const GLKVector2 texelUV = surfaceSTToTexelUV_bilinearQuad(
		GLKVector2Make((float)pixelX / info->destWidth, (float)pixelY / info->destHeight),
		info->points,
		kPointUVs
	);
	
	int nearestTexelX = (int)lroundf(texelUV.s * info->srcWidth_f - 0.5f);
	int nearestTexelY = (int)lroundf(texelUV.t * info->srcHeight_f - 0.5f);
	
	bool texelValid = normalizeTexelXY<tUVMode>(&nearestTexelX, &nearestTexelY, info->srcWidth_i, info->srcHeight_i);
	if (!texelValid)
		return;
	
	const int texelIndex = nearestTexelY * info->srcWidth_i + nearestTexelX;
	const UInt8 *texelBytes = &info->srcBytes[texelIndex * kBytesPerPixel];
	
	//UInt8 nearestTexelSample[kBytesPerPixel];
	copyBytesToPixelFromTexel<tComponentCount>(pixelByteBuffer, texelBytes);
	
	// @debug: show UVs directly
	//pixelByteBuffer[0] = fabsf(texelUV.x) * 255.0f;
	//pixelByteBuffer[1] = fabsf(texelUV.y) * 255.0f;
	//pixelByteBuffer[2] = (texelUV.x < 0 ? 127 : 0) + (texelUV.y < 0 ? 127 : 0);
	//pixelByteBuffer[3] = 255;
}

/// Returned image data buffer must be freed with free() by the caller.
template<OutsideOfQuadUVMode tUVMode, int tComponentCount>
CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4])
{
	static const size_t kBytesPerPixel = tComponentCount;
	
	const size_t srcByteCount = CFDataGetLength(srcData);
	assert(srcByteCount == (srcWidth * srcHeight * kBytesPerPixel));
	
	const UInt8 *srcBytes = CFDataGetBytePtr(srcData);
	const struct DestImageGenInfo info = {
		.srcWidth_i = srcWidth, .srcHeight_i = srcHeight,
		.srcWidth_f = (float)srcWidth, .srcHeight_f = (float)srcHeight,
		.srcBytes = srcBytes,
		.destWidth = destWidth, .destHeight = destHeight,
		.point1 = points[0],
		.point2 = points[1],
		.point3 = points[2],
		.point4 = points[3]
	};
	
	unsigned int pixelCount = destWidth * destHeight;
	UInt8 *byteBuffer = (UInt8 *)calloc(pixelCount, kBytesPerPixel); // transparent black-initialized
	
	for (int pixelX = destWidth - 1; pixelX >= 0; --pixelX) {
		for (int pixelY = destHeight - 1; pixelY >= 0; --pixelY) {
			int pixelI = pixelY * destWidth + pixelX;
			
			off_t position = pixelI * kBytesPerPixel;
			UInt8 *pixelBytes = &byteBuffer[position];
			
			genDestImagePixelBytes<tUVMode, tComponentCount>(&info, pixelX, pixelY, pixelBytes);
		}
	}
	
	const size_t byteCount = pixelCount * kBytesPerPixel;
	CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, byteBuffer, byteCount, kCFAllocatorMalloc);
	return data;
}

template<OutsideOfQuadUVMode tUVMode>
inline CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4], int channelCount)
{
	switch (channelCount)
	{
		case 1:
			return createDestImageData<tUVMode, 1>(srcWidth, srcHeight, srcData, destWidth, destHeight, points);
		case 2:
			return createDestImageData<tUVMode, 2>(srcWidth, srcHeight, srcData, destWidth, destHeight, points);
		case 3:
			return createDestImageData<tUVMode, 3>(srcWidth, srcHeight, srcData, destWidth, destHeight, points);
		case 4:
			return createDestImageData<tUVMode, 4>(srcWidth, srcHeight, srcData, destWidth, destHeight, points);
		
		default:
			assert(channelCount >= 1 && channelCount <= 4);
			return NULL;
	}
}

CFDataRef createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, GLKVector2 points[4], OutsideOfQuadUVMode uvMode, int channelCount)
{
	switch (uvMode)
	{
		case OutsideOfQuadUVWrap:
			return createDestImageData<OutsideOfQuadUVWrap>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, channelCount);
		case OutsideOfQuadUVClamp:
			return createDestImageData<OutsideOfQuadUVClamp>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, channelCount);
		case OutsideOfQuadUVSkip:
			return createDestImageData<OutsideOfQuadUVSkip>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, channelCount);
		
		default:
			assert(false); // not a valid uvMode
			return NULL;
	}
}
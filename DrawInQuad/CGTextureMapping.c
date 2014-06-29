#include "CGTextureMapping.h"

#include <stdbool.h>
#include <assert.h>

#include "GLKMathExtensions.h"



#pragma mark Constants

/// This blit only works with 4 components per pixel (RGBA).
static const int kComponentCount = 4;



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
	
	bool wrapUVs;
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
	return v > l && v < h;
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

static inline GLKVector2 GLKVector2FromCGPoint(CGPoint point) {
	return GLKVector2Make(point.x, point.y);
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

void genDestImagePixelBytes(const struct DestImageGenInfo *info, const int pixelX, const int pixelY, UInt8 *pixelByteBuffer)
{
	static const int kBytesPerPixel = kComponentCount;
	
	const struct DestImageGenInfo genInfo = *info;
	
	static const GLKVector2 kPointUVs[4] = {
		(GLKVector2){ .x = 0.0f, .y = 0.0f },
		(GLKVector2){ .x = 0.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 0.0f },
	};
	const GLKVector2 texelUV = surfaceSTToTexelUV_bilinearQuad(
		GLKVector2Make((CGFloat)pixelX / genInfo.destWidth, (CGFloat)pixelY / genInfo.destHeight),
		genInfo.points,
		kPointUVs
	);
	
	int nearestTexelX = roundf(texelUV.s * genInfo.srcWidth_f - 0.5f);
	int nearestTexelY = roundf(texelUV.t * genInfo.srcHeight_f - 0.5f);
	
	if (genInfo.wrapUVs) {
		if (!withini(nearestTexelX, 0, genInfo.srcWidth_i - 1))
			nearestTexelX = modulo(nearestTexelX, genInfo.srcWidth_i);
		if (!withini(nearestTexelY, 0, genInfo.srcHeight_i - 1))
			nearestTexelY = modulo(nearestTexelY, genInfo.srcHeight_i);
	}
	else {
		if (!withini(nearestTexelX, 0, genInfo.srcWidth_i - 1))
			nearestTexelX = clampi(nearestTexelX, 0, genInfo.srcWidth_i - 1);
		if (!withini(nearestTexelY, 0, genInfo.srcHeight_i - 1))
			nearestTexelY = clampi(nearestTexelY, 0, genInfo.srcHeight_i - 1);
	}
	
	const int texelIndex = nearestTexelY * genInfo.srcWidth_i + nearestTexelX;
	const UInt8 *texelBytes = &genInfo.srcBytes[texelIndex * kBytesPerPixel];
	
	//UInt8 nearestTexelSample[kBytesPerPixel];
	pixelByteBuffer[0] = texelBytes[0];
	pixelByteBuffer[1] = texelBytes[1];
	pixelByteBuffer[2] = texelBytes[2];
	pixelByteBuffer[3] = texelBytes[3];
	
	//memcpy(pixelByteBuffer, nearestTexelSample, kBytesPerPixel);
	// @debug: show UVs directly
	//pixelByteBuffer[0] = fabsf(texelUV.x) * 255.0f;
	//pixelByteBuffer[1] = fabsf(texelUV.y) * 255.0f;
	//pixelByteBuffer[2] = (texelUV.x < 0 ? 127 : 0) + (texelUV.y < 0 ? 127 : 0);
	//pixelByteBuffer[3] = 255;
}

/// Returned image data buffer must be freed with free() by the caller.
UInt8 * createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, CGPoint points[4], bool wrapUVs, size_t *out_byteCount)
{
	const UInt8 *srcBytes = CFDataGetBytePtr(srcData);
	const struct DestImageGenInfo info = {
		.srcWidth_i = srcWidth, .srcHeight_i = srcHeight,
		.srcWidth_f = srcWidth, .srcHeight_f = srcHeight,
		.srcBytes = srcBytes,
		.destWidth = destWidth, .destHeight = destHeight,
		.point1 = GLKVector2FromCGPoint(points[0]),
		.point2 = GLKVector2FromCGPoint(points[1]),
		.point3 = GLKVector2FromCGPoint(points[2]),
		.point4 = GLKVector2FromCGPoint(points[3]),
		.wrapUVs = wrapUVs,
	};
	
	unsigned int pixelCount = destWidth * destHeight;
	size_t byteCount = pixelCount * 4;
	UInt8 *byteBuffer = malloc(byteCount);
	
	const size_t kBytesPerPixel = kComponentCount;
	
	for (int pixelX = destWidth - 1; pixelX >= 0; --pixelX) {
		for (int pixelY = destHeight - 1; pixelY >= 0; --pixelY) {
			int pixelI = pixelY * destWidth + pixelX;
			
			off_t position = pixelI * kBytesPerPixel;
			UInt8 *pixelBytes = &byteBuffer[position];
			
			genDestImagePixelBytes(&info, pixelX, pixelY, pixelBytes);
		}
	}
	
	if (out_byteCount != NULL)
		*out_byteCount = byteCount;
	
	return byteBuffer;
}

#include "CGTextureMapping.h"

#include <stdbool.h>
#include <assert.h>

#include "GLKMathExtensions.h"



#pragma mark Constants

static const int kComponentCount = 4;



#pragma mark Intermediate Data

struct DestImageGenInfo {
	int srcWidth, srcHeight;
	CFDataRef srcData;
	
	int destWidth, destHeight;
	
	GLKVector2 points[4];
	
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

size_t genDestImagePixelBytesAtPosition(struct DestImageGenInfo *info, void *buffer, off_t position, size_t requestedByteCount)
{
	struct DestImageGenInfo genInfo = *info;
	
	const int kBytesPerPixel = 4;
	
	UInt8 *byteBuffer = (UInt8 *)buffer;
	
	const unsigned int width = genInfo.destWidth,
		height = genInfo.destHeight,
		pixelCount = width * height;
	
	const unsigned int pixelIndex = (unsigned int)(position / kBytesPerPixel);
	if (pixelIndex >= pixelCount)
		return 0;
	const unsigned int pixelX = pixelIndex % width,
		pixelY = pixelIndex / width;
	
	static const GLKVector2 kPointUVs[4] = {
		(GLKVector2){ .x = 0.0f, .y = 0.0f },
		(GLKVector2){ .x = 0.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 1.0f },
		(GLKVector2){ .x = 1.0f, .y = 0.0f },
	};
	const GLKVector2 texelUV = surfaceSTToTexelUV_barycentricQuad(
		GLKVector2Make((CGFloat)pixelX / width, (CGFloat)pixelY / height),
		genInfo.points,
		kPointUVs
	);
	
	int nearestTexelXY[2] = {
		roundf(texelUV.s * genInfo.srcWidth - 0.5f),
		roundf(texelUV.t * genInfo.srcHeight - 0.5f)
	};
	if (genInfo.wrapUVs) {
		if (!withini(nearestTexelXY[0], 0, genInfo.srcWidth - 1))
			nearestTexelXY[0] = modulo(nearestTexelXY[0], genInfo.srcWidth);
		if (!withini(nearestTexelXY[1], 0, genInfo.srcHeight - 1))
			nearestTexelXY[1] = modulo(nearestTexelXY[1], genInfo.srcHeight);
	}
	else {
		if (!withini(nearestTexelXY[0], 0, genInfo.srcWidth - 1))
			nearestTexelXY[0] = clampi(nearestTexelXY[0], 0, genInfo.srcWidth - 1);
		if (!withini(nearestTexelXY[1], 0, genInfo.srcHeight - 1))
			nearestTexelXY[1] = clampi(nearestTexelXY[1], 0, genInfo.srcHeight - 1);
	}
	
	const int texelIndex = nearestTexelXY[1] * genInfo.srcWidth + nearestTexelXY[0];
	
	UInt8 nearestTexelSample[4];
	CFDataGetBytes(
		genInfo.srcData,
		CFRangeMake(texelIndex * kBytesPerPixel, kBytesPerPixel),
		nearestTexelSample
	);
	
	const unsigned int pixelByteOffset = position % kBytesPerPixel;
	const size_t byteCount = kBytesPerPixel - pixelByteOffset;
	
	assert(kComponentCount == 4); // This blit only works with 4 components per pixel (RGBA).
	
	switch (pixelByteOffset)
	{
		case 0:
			byteBuffer[0] = nearestTexelSample[0];
			//byteBuffer[0] = fabsf(texelUV.x) * 255.0f; // @debug: show UVs directly
		case 1:
			byteBuffer[1] = nearestTexelSample[1];
			//byteBuffer[1] = fabsf(texelUV.y) * 255.0f; // @debug: show UVs directly
		case 2:
			byteBuffer[2] = nearestTexelSample[2];
			//byteBuffer[2] = (texelUV.x < 0 ? 127 : 0) + (texelUV.y < 0 ? 127 : 0); // @debug: show UVs directly
		case 3:
			byteBuffer[3] = nearestTexelSample[3];
			//byteBuffer[3] = 255; // @debug: show UVs directly
			break;
		
		default:
			assert(pixelByteOffset < 4);
	}
	
	return byteCount;
}

/// Returned image data buffer must be freed with free() by the caller.
UInt8 * createDestImageData(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, CGPoint points[4], bool wrapUVs, size_t *out_byteCount)
{
	unsigned int pixelCount = destWidth * destHeight;
	size_t byteCount = pixelCount * 4;
	
	UInt8 *byteBuffer = malloc(byteCount);
	
	struct DestImageGenInfo info = {
		.srcWidth = srcWidth, .srcHeight = srcHeight,
		.srcData = srcData,
		.destWidth = destWidth, .destHeight = destHeight,
		.wrapUVs = wrapUVs,
	};
	info.points[0] = GLKVector2FromCGPoint(points[0]);
	info.points[1] = GLKVector2FromCGPoint(points[1]);
	info.points[2] = GLKVector2FromCGPoint(points[2]);
	info.points[3] = GLKVector2FromCGPoint(points[3]);
	
	size_t bytesPerPixel = kComponentCount;
	
	for (int pixelI = pixelCount - 1; pixelI >= 0; --pixelI) {
		off_t position = pixelI * bytesPerPixel;
		
		size_t bytesGenerated = genDestImagePixelBytesAtPosition(&info, &byteBuffer[position], position, bytesPerPixel);
		assert(bytesGenerated == bytesPerPixel); // Fewer bytes generated than requested.
	}
	
	if (out_byteCount != NULL)
		*out_byteCount = byteCount;
	
	return byteBuffer;
}

#include "CGTextureMapping.h"

#include <stdbool.h>
#include <assert.h>

#include "GLKMathExtensions.h"



#pragma mark Constants

static const uint8_t kInvalidBoolValue = 0xff;
static const float kJustUnder1_0f = nexttowardf(1.0f, 0.0);


#pragma mark Intermediate Data

/// `Aft`: Aft end
/// `Fore`: Fore end
/// `Star`: Starboard side
/// `Port`: Port side
struct DestImageGenInfo {
	int srcWidth_i, srcHeight_i;
	GLKVector2 srcSize_v2;
	const UInt8 * srcBytes;
	
	GLKVector2 destSizeReciprocal_v2;
	
	union {
		GLKVector2 points[4];
		struct { GLKVector2 pointAftStar, pointAftPort, pointForeStar, pointForePort; };
	};
	
	GLKVector2 segmentAftDelta, segmentForeDelta;
	float segmentAftLengthSqr, segmentForeLengthSqr;
	
	union {
		GLKVector2 pointUVs[4];
		/// specified in standard clockwise OpenGL quad/quadstrip order: back-right, back-left, front-right, front-left
		struct { GLKVector2 pointUV0, pointUV1, pointUV2, pointUV3; };
	};
};



#pragma mark Util Functions

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

static inline int modulo_i(int dividendA, int divisorN)
{
	if (divisorN < 0) // you can check for divisorN == 0 separately and do what you want
		return modulo_i(-dividendA, -divisorN);
	
	int ret = dividendA % divisorN;
	if (ret < 0)
		ret += divisorN;
	
	return ret;
}
static inline float modulo_f(float dividendA, float divisorN)
{
	if (divisorN < 0.0f) // you can check for divisorN == 0 separately and do what you want
		return modulo_f(-dividendA, -divisorN);
	
	float ret = fmodf(dividendA, divisorN);
	if (ret < 0)
		ret += divisorN;
	
	return ret;
}

static inline int clamp_i(int v, int l, int h)
{
	if (v < l)
		return l;
	else if (v > h)
		return h;
	else
		return v;
}
static inline float clamp_f(float v, float l, float h)
{
	if (v < l)
		return l;
	else if (v > h)
		return h;
	else
		return v;
}
static inline float clamp0ToJustUnder1_f(float v) {
	return clamp_f(v, 0.0f, kJustUnder1_0f);
}

static inline bool within_i(int v, int l, int h)
{
	return v >= l && v <= h;
}
static inline bool inRangeInclusiveExclusive_f(float v, float lInclusive, float hExclusive)
{
	return v >= lInclusive && v < hExclusive;
}
static inline bool inRange0ToJustUnder1_f(float v) {
	return inRangeInclusiveExclusive_f(v, 0.0f, 1.0f);
}

static inline float ratioAndNearestPointAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 segmentDelta, float segmentLengthSqr, GLKVector2 *out_nearestPoint)
{
	GLKVector2 freeToADelta = GLKVector2Subtract(freePoint, segmentAPoint);
	
	float ratioAlongSegment = GLKVector2DotProduct(freeToADelta, segmentDelta) / segmentLengthSqr;
	
	if (ratioAlongSegment <= 0.0f)
		*out_nearestPoint = segmentAPoint;
	else if (ratioAlongSegment >= 1.0f)
		*out_nearestPoint = segmentBPoint;
	else
		*out_nearestPoint = GLKVector2Add(segmentAPoint, GLKVector2MultiplyScalar(segmentDelta, ratioAlongSegment));
	
	return ratioAlongSegment;
}
/// segmentDelta and segmentLengthSqr calculated on-the-fly
static inline float ratioAndNearestPointAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 *out_nearestPoint) {
	GLKVector2 segmentDelta = GLKVector2Subtract(segmentBPoint, segmentAPoint);
	float segmentLengthSqr = GLKVector2LengthSqr(segmentDelta);
	return ratioAndNearestPointAlongSegment(freePoint, segmentAPoint, segmentBPoint, segmentDelta, segmentLengthSqr, out_nearestPoint);
}

static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 segmentDelta, float segmentLengthSqr)
{
	GLKVector2 freeToADelta = GLKVector2Subtract(freePoint, segmentAPoint);
	
	float ratioAlongSegment = GLKVector2DotProduct(freeToADelta, segmentDelta) / segmentLengthSqr;
	return ratioAlongSegment;
}
/// segmentDelta and segmentLengthSqr calculated on-the-fly
static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint) {
	GLKVector2 segmentDelta = GLKVector2Subtract(segmentBPoint, segmentAPoint);
	float segmentLengthSqr = GLKVector2LengthSqr(segmentDelta); // @warning: potentially zero, causings NaN to get returned
	return ratioAlongSegment(freePoint, segmentAPoint, segmentBPoint, segmentDelta, segmentLengthSqr);
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

#pragma clang diagnostic pop // ignored "-Wunused-function"


#pragma mark Texture Mapping Functions

/// @return: Whether the texture coordinate could potentially be normalized (`true`), or if it was too far out of range to be handled (`false`).
template<OutsideOfQuadUVMode tUVMode> bool isTexelCoordNormalizable(const float &coord);
template<> inline bool isTexelCoordNormalizable<OutsideOfQuadUVWrap>(const float &coord) { return true; }
template<> inline bool isTexelCoordNormalizable<OutsideOfQuadUVClamp>(const float &coord) { return true; }
template<> inline bool isTexelCoordNormalizable<OutsideOfQuadUVSkip>(const float &coord)
{
	return inRange0ToJustUnder1_f(coord);
}

/// @return: Whether the texture coordinate could be and was normalized (`true`), or if it was too far out of range to be handled (`false`).
template<OutsideOfQuadUVMode tUVMode> void normalizeTexelCoord(float &coord);
template<> inline void normalizeTexelCoord<OutsideOfQuadUVWrap>(float &coord)
{
	if (!inRange0ToJustUnder1_f(coord))
		coord = modulo_f(coord, 1.0f);
}
template<> inline void normalizeTexelCoord<OutsideOfQuadUVClamp>(float &coord)
{
	if (!inRange0ToJustUnder1_f(coord))
		coord = clamp0ToJustUnder1_f(coord);
}
template<> inline void normalizeTexelCoord<OutsideOfQuadUVSkip>(float &coord) { /* no-op */ }

template<OutsideOfTextureSTMode tUVMode> void normalizeTexelST(float st[2]);
template<> inline void normalizeTexelST<OutsideOfTextureSTWrap>(float st[2])
{
	if (!inRange0ToJustUnder1_f(st[0]))
		st[0] = modulo_f(st[0], 1.0f);
	if (!inRange0ToJustUnder1_f(st[1]))
		st[1] = modulo_f(st[1], 1.0f);
}
template<> inline void normalizeTexelST<OutsideOfTextureSTClamp>(float st[2])
{
	if (!inRange0ToJustUnder1_f(st[0]))
		st[0] = clamp0ToJustUnder1_f(st[0]);
	if (!inRange0ToJustUnder1_f(st[1]))
		st[1] = clamp0ToJustUnder1_f(st[1]);
}

/// Based on a loose understanding of Wikipedia's article on Bilinear interpolation (https://en.wikipedia.org/wiki/Bilinear_interpolation).
/// 	Probably not the best algoritm for this— works, but with more distortion as the points become less square.
/// 	Seems to show better results when the left and right sides of the points quad are parallel.
template<OutsideOfQuadUVMode tUVMode>
GLKVector2 surfaceSTToTexelUV_bilinearQuad(const struct DestImageGenInfo &info, const GLKVector2 surfaceST)
{
	GLKVector2 nearestPointOnAft, nearestPointOnFore;
	float ratioAlongAft = ratioAndNearestPointAlongSegment(
		surfaceST,
		info.pointAftStar, info.pointAftPort,
		info.segmentAftDelta, info.segmentAftLengthSqr,
		&nearestPointOnAft
	);
	float ratioAlongFore = ratioAndNearestPointAlongSegment(
		surfaceST,
		info.pointForeStar, info.pointForePort,
		info.segmentForeDelta, info.segmentForeLengthSqr,
		&nearestPointOnFore
	);
	
	float ratioAlongNearestAftToNearestFore = ratioAlongSegment(surfaceST, nearestPointOnAft, nearestPointOnFore);
	bool vCoordValid = isTexelCoordNormalizable<tUVMode>(ratioAlongNearestAftToNearestFore);
	if (!vCoordValid)
		return GLKVector2Invalid;
	
	normalizeTexelCoord<tUVMode>(ratioAlongNearestAftToNearestFore);
	
	float lerpedAftForeRatios = ratioAlongAft + (ratioAlongFore - ratioAlongAft) * ratioAlongNearestAftToNearestFore;
	bool uCoordValid = isTexelCoordNormalizable<tUVMode>(lerpedAftForeRatios);
	if (!uCoordValid)
		return GLKVector2Invalid;
	
	GLKVector2 uvOfNearestPointOnAft = GLKVector2Lerp(info.pointUV0, info.pointUV1, ratioAlongAft);
	GLKVector2 uvOfNearestPointOnFore = GLKVector2Lerp(info.pointUV2, info.pointUV3, ratioAlongFore);
	GLKVector2 texelUV = GLKVector2Lerp(uvOfNearestPointOnAft, uvOfNearestPointOnFore, ratioAlongNearestAftToNearestFore);
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

GLKVector2 surfaceSTToTexelUV_barycentricQuad(const struct DestImageGenInfo &info, const GLKVector2 surfaceST)
{
	static const int kAftStarTriInQuadIndices[3] = { 0, 1, 2 };
	static const int kForePortTriInQuadIndices[3] = { 1, 3, 2 };
	
	//// @source http://stackoverflow.com/questions/1560492/how-to-tell-whether-a-point-is-to-the-right-or-left-side-of-a-line
	float lineVsPointCross = GLKVector2CrossProduct(
		GLKVector2Subtract(info.pointForeStar, info.pointAftPort),
		GLKVector2Subtract(surfaceST, info.pointAftPort)
	);
	bool inAftStarTri = lineVsPointCross > 0.0f;
	
	const int *triInQuadIndices = inAftStarTri ? kAftStarTriInQuadIndices : kForePortTriInQuadIndices;
	return surfaceSTToTexelUV_barycentricTri(
		surfaceST,
		(GLKVector2[3]){
			info.points[triInQuadIndices[0]],
			info.points[triInQuadIndices[1]],
			info.points[triInQuadIndices[2]]
		},
		(GLKVector2[3]){
			info.pointUVs[triInQuadIndices[0]],
			info.pointUVs[triInQuadIndices[1]],
			info.pointUVs[triInQuadIndices[2]]
		}
	);
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

template<OutsideOfQuadUVMode tUVMode, OutsideOfTextureSTMode tSTMode, int tComponentCount>
void genDestImagePixelBytes(const struct DestImageGenInfo &info, const int pixelX, const int pixelY, UInt8 *pixelByteBuffer)
{
	static const int kBytesPerPixel = tComponentCount;
	
	const GLKVector2 &pixelST = GLKVector2Multiply(GLKVector2Make(pixelX, pixelY), info.destSizeReciprocal_v2);
	GLKVector2 texelST = surfaceSTToTexelUV_bilinearQuad<tUVMode>(info, pixelST);
	if (GLKVector2IsInvalid(texelST))
		return;
	
	normalizeTexelST<tSTMode>(texelST.v);
	
	GLKVector2 texelXY = GLKVector2Multiply(texelST, info.srcSize_v2);
	int nearestTexelX = (texelXY.x >= 0.0f) ? (int)texelXY.x : ((int)texelXY.x - 1),
		nearestTexelY = (texelXY.y >= 0.0f) ? (int)texelXY.y : ((int)texelXY.y - 1);
	
	const int texelIndex = nearestTexelY * info.srcWidth_i + nearestTexelX;
	const UInt8 *texelBytes = &info.srcBytes[texelIndex * kBytesPerPixel];
	
	//UInt8 nearestTexelSample[kBytesPerPixel];
	copyBytesToPixelFromTexel<tComponentCount>(pixelByteBuffer, texelBytes);
	
	// @debug: show UVs directly
	//pixelByteBuffer[0] = fabsf(texelST.x) * 255.0f;
	//pixelByteBuffer[1] = fabsf(texelST.y) * 255.0f;
	//pixelByteBuffer[2] = (texelST.x < 0 ? 127 : 0) + (texelST.y < 0 ? 127 : 0);
	//pixelByteBuffer[3] = 255;
}

UInt8 * defaultDestBufferAllocator(void *_, int pixelCount, size_t bytesPerPixel, bool *out_takeOwnership)
{
	UInt8 *byteBuffer = (UInt8 *)calloc(pixelCount, bytesPerPixel); // transparent black-initialized
	
	*out_takeOwnership = true;
	return byteBuffer;
}

/// Returned image data buffer must be freed with free() by the caller.
template<OutsideOfQuadUVMode tUVMode, OutsideOfTextureSTMode tSTMode, int tComponentCount>
CFDataRef cgTextureMappingBlit(
	int srcWidth, int srcHeight, CFDataRef srcData,
	int destWidth, int destHeight,
	const GLKVector2 points[4], const GLKVector2 pointUVs[4],
	DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo
)
{
	static const size_t kBytesPerPixel = tComponentCount;
	
	if (pointUVs == NULL)
		pointUVs = kDefaultPointUVs;
	if (destBufferAllocator == NULL)
		destBufferAllocator = defaultDestBufferAllocator;
	
	const size_t srcByteCount = CFDataGetLength(srcData);
	assert(srcByteCount == (srcWidth * srcHeight * kBytesPerPixel));
	
	const UInt8 *srcBytes = CFDataGetBytePtr(srcData);
	struct DestImageGenInfo info = {
		.srcWidth_i = srcWidth, .srcHeight_i = srcHeight,
		.srcSize_v2 = GLKVector2Make(srcWidth, srcHeight),
		.srcBytes = srcBytes,
		.destSizeReciprocal_v2 = GLKVector2Make(1.0f / destWidth, 1.0f / destHeight),
		.pointAftStar = points[0], .pointAftPort = points[1], .pointForeStar = points[2], .pointForePort = points[3],
		.pointUV0 = pointUVs[0], .pointUV1 = pointUVs[1], .pointUV2 = pointUVs[2], .pointUV3 = pointUVs[3],
	};
	info.segmentAftDelta = GLKVector2Subtract(info.pointAftPort, info.pointAftStar);
	info.segmentForeDelta = GLKVector2Subtract(info.pointForePort, info.pointForeStar);
	// hack to avoid `… / 0 = NaN` issues:
	info.segmentAftLengthSqr = GLKVector2AllEqualToScalar(info.segmentAftDelta, 0.0f) ? FLT_MIN : GLKVector2LengthSqr(info.segmentAftDelta);
	info.segmentForeLengthSqr = GLKVector2AllEqualToScalar(info.segmentForeDelta, 0.0f) ? FLT_MIN : GLKVector2LengthSqr(info.segmentForeDelta);
	
	unsigned int pixelCount = destWidth * destHeight;
	
	// kinda awesome trick to check that the destBufferAllocator actually changed the value of its `out_takeOwnership` arg
	union { bool should; uint8_t asUint8; } takeOwnership = { .asUint8 = kInvalidBoolValue };
	UInt8 *byteBuffer = destBufferAllocator(destBufferAllocatorInfo, pixelCount, kBytesPerPixel, &takeOwnership.should);
	assert(takeOwnership.asUint8 != kInvalidBoolValue); // you really do have to set the variable
	
	for (int pixelX = destWidth - 1; pixelX >= 0; --pixelX) {
		for (int pixelY = destHeight - 1; pixelY >= 0; --pixelY) {
			int pixelI = pixelY * destWidth + pixelX;
			
			off_t position = pixelI * kBytesPerPixel;
			UInt8 *pixelBytes = &byteBuffer[position];
			
			genDestImagePixelBytes<tUVMode, tSTMode, tComponentCount>(info, pixelX, pixelY, pixelBytes);
		}
	}
	
	const size_t byteCount = pixelCount * kBytesPerPixel;
	CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, byteBuffer, byteCount, takeOwnership.should ? kCFAllocatorMalloc : kCFAllocatorNull);
	return data;
}

template<OutsideOfQuadUVMode tUVMode, OutsideOfTextureSTMode tSTMode>
inline CFDataRef cgTextureMappingBlit(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, const GLKVector2 points[4], const GLKVector2 pointUVs[4], int channelCount, DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo) {
	switch (channelCount) {
		case 1: return cgTextureMappingBlit<tUVMode, tSTMode, 1>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, destBufferAllocator, destBufferAllocatorInfo);
		case 2: return cgTextureMappingBlit<tUVMode, tSTMode, 2>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, destBufferAllocator, destBufferAllocatorInfo);
		case 3: return cgTextureMappingBlit<tUVMode, tSTMode, 3>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, destBufferAllocator, destBufferAllocatorInfo);
		case 4: return cgTextureMappingBlit<tUVMode, tSTMode, 4>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, destBufferAllocator, destBufferAllocatorInfo);
		default:
			assert(channelCount >= 1 && channelCount <= 4);
			return NULL;
	}
}
template<OutsideOfQuadUVMode tUVMode>
inline CFDataRef cgTextureMappingBlit(
	int srcWidth, int srcHeight, CFDataRef srcData,
	int destWidth, int destHeight,
	const GLKVector2 points[4], const GLKVector2 pointUVs[4],
	OutsideOfTextureSTMode stMode, int channelCount,
	DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo
) {
	switch (stMode) {
		case OutsideOfTextureSTWrap: return cgTextureMappingBlit<tUVMode, OutsideOfTextureSTWrap>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, channelCount, destBufferAllocator, destBufferAllocatorInfo);
		case OutsideOfTextureSTClamp: return cgTextureMappingBlit<tUVMode, OutsideOfTextureSTClamp>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, channelCount, destBufferAllocator, destBufferAllocatorInfo);
		default:
			assert(false); // not a valid stMode
			return NULL;
	}
}
CFDataRef cgTextureMappingBlit(int srcWidth, int srcHeight, CFDataRef srcData, int destWidth, int destHeight, const GLKVector2 points[4], const GLKVector2 pointUVs[4], OutsideOfQuadUVMode uvMode, OutsideOfTextureSTMode stMode, int channelCount, DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo) {
	switch (uvMode) {
		case OutsideOfQuadUVWrap: return cgTextureMappingBlit<OutsideOfQuadUVWrap>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, stMode, channelCount, destBufferAllocator, destBufferAllocatorInfo);
		case OutsideOfQuadUVClamp: return cgTextureMappingBlit<OutsideOfQuadUVClamp>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, stMode, channelCount, destBufferAllocator, destBufferAllocatorInfo);
		case OutsideOfQuadUVSkip: return cgTextureMappingBlit<OutsideOfQuadUVSkip>(srcWidth, srcHeight, srcData, destWidth, destHeight, points, pointUVs, stMode, channelCount, destBufferAllocator, destBufferAllocatorInfo);
		default:
			assert(false); // not a valid uvMode
			return NULL;
	}
}

#pragma once

#include <CoreFoundation/CFData.h>
#include <GLKit/GLKVector2.h>



typedef enum OutsideOfQuadUVMode {
	OutsideOfQuadUVWrap,
	OutsideOfQuadUVClamp,
	OutsideOfQuadUVSkip,
} OutsideOfQuadUVMode;

typedef enum OutsideOfTextureSTMode {
	OutsideOfTextureSTWrap,
	OutsideOfTextureSTClamp,
} OutsideOfTextureSTMode;


/// In order to use the `out_takeOwnership` mechanism, the returned data must've been allocated with malloc(), realloc(), or calloc().
/// @arg out_takeOwnership: Required out-param specifying if createDestImageData() should take ownership of the byte buffer (if it should ensure it's `free()`ed via CFData's deallocator).
/// @return: A buffer in which to store the pixel data, of at least `(pixelCount * bytesPerPixel)` in size.
typedef UInt8 * DestBufferAllocator(void *info, int pixelCount, size_t bytesPerPixel, bool *out_takeOwnership);

static const GLKVector2 kDefaultPointUVs[4] = {
	(GLKVector2){ .x = 1.0f, .y = 0.0f },
	(GLKVector2){ .x = 0.0f, .y = 0.0f },
	(GLKVector2){ .x = 1.0f, .y = 1.0f },
	(GLKVector2){ .x = 0.0f, .y = 1.0f },
};


#ifdef __cplusplus
	/// @arg points: Specified in standard OpenGL quad/quadstrip order: back-right, back-left, front-right, front-left
	/// @arg pointUVs: The UV coordinates for each point.  If NULL, will use kDefaultPointUVs.
	/// @arg destBufferAllocator: A DestBufferAllocator function to use for allocation of the memory that'll be returned, or NULL to use the default allocater.
	/// @arg destBufferAllocatorInfo: A pointer to data of any type or NULL.  When the destBufferAllocator is called, it is sent this pointer.
	template<OutsideOfQuadUVMode tUVMode, OutsideOfTextureSTMode tSTMode, int tComponentCount>
	CFDataRef cgTextureMappingBlit(
		int srcWidth, int srcHeight, CFDataRef srcData,
		int destWidth, int destHeight,
		const GLKVector2 points[4], const GLKVector2 pointUVs[4],
		DestBufferAllocator destBufferAllocator=NULL, void *destBufferAllocatorInfo=NULL
	);
#endif


#ifdef __cplusplus
	extern "C" {
#endif

CFDataRef cgTextureMappingBlit(
	int srcWidth, int srcHeight, CFDataRef srcData,
	int destWidth, int destHeight,
	const GLKVector2 points[4], const GLKVector2 pointUVs[4],
	OutsideOfQuadUVMode uvMode, OutsideOfTextureSTMode stMode, int channelCount,
	DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo
);

#ifdef __cplusplus
	} // extern "C"
#endif

#pragma once

#include <CoreFoundation/CFData.h>
#include <GLKit/GLKVector2.h>



typedef enum OutsideOfQuadUVMode
{
	OutsideOfQuadUVWrap,
	OutsideOfQuadUVClamp,
	OutsideOfQuadUVSkip,
} OutsideOfQuadUVMode;


/// In order to use the `out_takeOwnership` mechanism, the returned data must've been allocated with malloc(), realloc(), or calloc().
/// @arg out_takeOwnership: Required out-param specifying if createDestImageData() should take ownership of the byte buffer (if it should ensure it's `free()`ed via CFData's deallocator).
/// @return: A buffer in which to store the pixel data, of at least `(pixelCount * bytesPerPixel)` in size.
typedef UInt8 * DestBufferAllocator(void *info, int pixelCount, size_t bytesPerPixel, bool *out_takeOwnership);


#ifdef __cplusplus
	/// @arg points: Specified in standard OpenGL quad/quadstrip order: back-right, back-left, front-right, front-left
	template<OutsideOfQuadUVMode tUVMode, int tComponentCount>
	CFDataRef createDestImageData(
		int srcWidth, int srcHeight, CFDataRef srcData,
		int destWidth, int destHeight,
		GLKVector2 points[4],
		DestBufferAllocator destBufferAllocator=NULL, void *destBufferAllocatorInfo=NULL
	);
#endif


#ifdef __cplusplus
	extern "C" {
#endif

/// @arg destBufferAllocator: A DestBufferAllocator function to use for allocation of the memory that'll be returned, or NULL to use the default allocater.
/// @arg destBufferAllocatorInfo: A pointer to data of any type or NULL.  When the destBufferAllocator is called, it is sent this pointer.
CFDataRef createDestImageData(
	int srcWidth, int srcHeight, CFDataRef srcData,
	int destWidth, int destHeight,
	GLKVector2 points[4],
	OutsideOfQuadUVMode uvMode, int channelCount,
	DestBufferAllocator destBufferAllocator, void *destBufferAllocatorInfo
);

#ifdef __cplusplus
	} // extern "C"
#endif

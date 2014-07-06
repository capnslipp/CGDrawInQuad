#pragma once

#include <math.h>



static const float kJustUnder1_0f = nexttowardf(1.0f, 0.0);



static inline int modulo_i(int dividendA, int divisorN);
static inline float modulo_f(float dividendA, float divisorN);

static inline int clamp_i(int v, int l, int h);
static inline float clamp_f(float v, float l, float h);
static inline float clamp0ToJustUnder1_f(float v);

static inline bool within_i(int v, int l, int h);
static inline bool inRangeInclusiveExclusive_f(float v, float lInclusive, float hExclusive);
static inline bool inRange0ToJustUnder1_f(float v);

static inline float ratioAndNearestPointAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 segmentDelta, float segmentLengthSqr, GLKVector2 *out_nearestPoint);
/// Less-efficient variant— segmentDelta and segmentLengthSqr are calculated on-the-fly
static inline float ratioAndNearestPointAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 *out_nearestPoint);

static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint, GLKVector2 segmentDelta, float segmentLengthSqr);
/// Less-efficient variant— segmentDelta and segmentLengthSqr are calculated on-the-fly
static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint);



#include "MathExtensions.inl"

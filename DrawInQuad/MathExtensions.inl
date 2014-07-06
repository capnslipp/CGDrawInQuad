


/// @source: http://stackoverflow.com/questions/4003232/how-to-code-a-modulo-operator-in-c-c-obj-c-that-handles-negative-numbers#answer-4003287
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
static inline float ratioAlongSegment(GLKVector2 freePoint, GLKVector2 segmentAPoint, GLKVector2 segmentBPoint) {
	GLKVector2 segmentDelta = GLKVector2Subtract(segmentBPoint, segmentAPoint);
	float segmentLengthSqr = GLKVector2LengthSqr(segmentDelta); // @warning: potentially zero, causings NaN to get returned
	return ratioAlongSegment(freePoint, segmentAPoint, segmentBPoint, segmentDelta, segmentLengthSqr);
}
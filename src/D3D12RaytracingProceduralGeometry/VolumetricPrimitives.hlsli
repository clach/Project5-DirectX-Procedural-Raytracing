// LOOKAT-1.9.4: Volumetric shapes intersection utilities. For this project, we are only concerned with Metaballs (aka "Blobs").
// More info here: https://www.scratchapixel.com/lessons/advanced-rendering/rendering-distance-fields/blobbies

#ifndef VOLUMETRICPRIMITIVESLIBRARY_H
#define VOLUMETRICPRIMITIVESLIBRARY_H

#include "RaytracingShaderHelper.hlsli"

// LOOKAT-1.9.4: Shockingly, a metaball is just a sphere!
struct Metaball
{
    float3 center;
    float  radius;
};

// DONE-3.4.2: Calculate a magnitude of an influence from a Metaball charge.
// This function should return a metaball potential, which is a float in range [0,1].
// 1) If the point is at the center, the potential is maximum = 1.
// 2) If it is at the radius or beyond, the potential is 0.
// 3) In between (i.e the distance from the center is between 0 and radius), consider using the a
//		quintic polynomial field function of the form 6x^5 - 15x^4 + 10x^3, such that x is the ratio 
//		of the distance from the center to the radius.
float CalculateMetaballPotential(in float3 position, in Metaball blob)
{
	float distToCenter = length(position - blob.center);
	if (distToCenter > blob.radius) 
	{
		return 0.f;
	}
	else if (distToCenter == 0) 
	{
		return 1.f;
	}
	else 
	{
		float x = (blob.radius - distToCenter) / blob.radius;
		return 6 * (x * x * x * x * x) - 15 * (x * x * x * x) + 10 * (x * x * x);
	}
}

// LOOKAT-1.9.4: Calculates field potential from all active metaballs. This is just the sum of all potentials.
float CalculateMetaballsPotential(in float3 position, in Metaball blobs[N_METABALLS])
{
    float sumFieldPotential = 0;

    for (UINT j = 0; j < N_METABALLS; j++)
    {
        sumFieldPotential += CalculateMetaballPotential(position, blobs[j]);
    }
    return sumFieldPotential;
}

// LOOKAT-1.9.4: Calculates a normal at a hit position via central differences.
float3 CalculateMetaballsNormal(in float3 position, in Metaball blobs[N_METABALLS])
{
    float e = 0.5773 * 0.00001; // epsilon

	// These are essentially derivatives in each axis. The derivative of a constant vector is ALWAYS perpendicular to it, so we 
	// can take it as its normal. The derivative can be computed as a direction of change: the potential at (position - e) - potential at (position + e)
    return normalize(float3(
        CalculateMetaballsPotential(position + float3(-e, 0, 0), blobs) -
        CalculateMetaballsPotential(position + float3(e, 0, 0), blobs),

        CalculateMetaballsPotential(position + float3(0, -e, 0), blobs) -
        CalculateMetaballsPotential(position + float3(0, e, 0), blobs),

        CalculateMetaballsPotential(position + float3(0, 0, -e), blobs) -
        CalculateMetaballsPotential(position + float3(0, 0, e), blobs)));
}

// LOOKAT-1.9.4: Initializes the metaballs in their correctly animated location.
void InitializeAnimatedMetaballs(out Metaball blobs[N_METABALLS], in float elapsedTime, in float cycleDuration)
{
    float3 keyFrameCenters[N_METABALLS][2] =
    {
        { float3(-0.3, -0.3, -0.4),float3(0.3,-0.3,-0.0) }, // begin center --> end center
        { float3(0.0, -0.2, 0.5), float3(0.0, 0.4, 0.5) },
        { float3(0.4,0.4, 0.4), float3(-0.4, 0.2, -0.4) }
    };

    // Metaball field radii of max influence
    float radii[N_METABALLS] = { 0.45, 0.55, 0.45 };

    // Calculate animated metaball center positions.
	float tAnimate = CalculateAnimationInterpolant(elapsedTime, cycleDuration);
    for (UINT j = 0; j < N_METABALLS; j++)
    {
        blobs[j].center = lerp(keyFrameCenters[j][0], keyFrameCenters[j][1], tAnimate);
        blobs[j].radius = radii[j];
    }
}

// DONE-3.4.2: Find the entry and exit points for all metaball bounding spheres combined.
// Remember that a metaball is just a solid sphere. Didn't we already do this somewhere else?
void TestMetaballsIntersection(in Ray ray, out float tmin, out float tmax, inout Metaball blobs[N_METABALLS])
{    
	tmin = INFINITY;
	tmax = -INFINITY;

	float bestTmin = tmin;
	float bestTmax = tmax;

	for (int i = 0; i < N_METABALLS; i++) 
	{
		if (RaySolidSphereIntersectionTest(ray, tmin, tmax, blobs[i].center, blobs[i].radius))
		{
			bestTmin = min(bestTmin, tmin);
			bestTmax = max(bestTmax, tmax);
		}
	}

	tmin = bestTmin;
	tmax = bestTmax;
}

// DONE-3.4.2: Test if a ray with RayFlags and segment <RayTMin(), RayTCurrent()> intersects metaball field.
// The test sphere traces through the metaball field until it hits a threshold isosurface.
// Returns true if we found a point. False otherwise.
// 1) Initialize a metaball array. See InitializeAnimatedMetaballs()
// 2) Test intersections on the metaballs to find the minimum t and the maximum t to raymarch between.
// 3) Use some number of steps (~128 is a good number for raymarching) to do the following:
//		a) Compute the total metaball potential over this point by summing ALL potentials of each metaball. 
//			See CalculateMetaballsPotential().
//		b) If the total potential crosses an isosurface threshold (defined on (0,1]), then we will potentially
//			render this point:
//			i) We compute the normal at this point (see CalculateMetaballsNormal())
//			ii) Only render this point if it is valid hit. See is_a_valid_hit(). 
//				If this condition fails, keep raymarching!
bool RayMetaballsIntersectionTest(in Ray ray, out float thit, out ProceduralPrimitiveAttributes attr, in float elapsedTime)
{
	thit = 0.0f;
	attr.normal = float3(0.0f, 0.0f, 0.0f);

	// Initialize metaball array
	Metaball blobs[N_METABALLS];
	InitializeAnimatedMetaballs(blobs, elapsedTime, 5.f);

	// Find min and max t for raymarching
	float tmin;
	float tmax;
	TestMetaballsIntersection(ray, tmin, tmax, blobs);

	// Ray march the metaballs to find intersection
	const int NUM_STEPS = 128;
	const float THRESHOLD = 0.25f;

	// make sure tmin <= tmax
	if (tmin > tmax) {
		float temp = tmin;
		tmin = tmax;
		tmax = temp;
	}

	float stepSize = (tmax - tmin) / (float)NUM_STEPS;

	for (float t = tmin; t <= tmax; t += stepSize) {
		float3 position = ray.origin + t * ray.direction;
		float potential = CalculateMetaballsPotential(position, blobs);
		if (potential > THRESHOLD) {
			float3 normal = CalculateMetaballsNormal(position, blobs);
			if (is_a_valid_hit(ray, t, normal)) {
				thit = t;
				attr.normal = normal;
				return true;
			}
		}
	}

    return false;
}

#endif // VOLUMETRICPRIMITIVESLIBRARY_H
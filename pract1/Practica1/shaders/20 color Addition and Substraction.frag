// COLOR ADDITION AND SUBSTRACTION
//
// How to draw a shape on top of another, and how will the layers
// below, affect the higher layers?
//
// In the previous shape drawing functions, we set the pixel
// value from the function. This time the shape function will
// just return a float value between 0.0 and 1.0 to indice the
// shape area. Later that value can be multiplied with some color
// and used in determining the final pixel color.

uniform vec3 iResolution;

// A function that returns the 1.0 inside the disk area
// returns 0.0 outside the disk area
// and has a smooth transition at the radius
float disk(vec2 r, vec2 center, float radius) {
	float distanceFromCenter = length(r-center);
	float outsideOfDisk = smoothstep( radius-0.005, radius+0.005, distanceFromCenter);
	float insideOfDisk = 1.0 - outsideOfDisk;
	return insideOfDisk;
}

void main(void)
{
	vec2 p = vec2(gl_FragCoord.xy / iResolution.xy);
	vec2 r =  2.0*vec2(gl_FragCoord.xy - 0.5*iResolution.xy)/iResolution.y;
	float xMax = iResolution.x/iResolution.y;	
	
	vec3 black = vec3(0.0);
	vec3 white = vec3(1.0);
	vec3 gray = vec3(0.3);
	vec3 col1 = vec3(0.216, 0.471, 0.698); // blue
	vec3 col2 = vec3(1.00, 0.329, 0.298); // red
	vec3 col3 = vec3(0.867, 0.910, 0.247); // yellow
	
	vec3 ret;
	float d;
	
	if(p.x < 1./3.) { // Part I
		// opaque layers on top of each other
		ret = gray;
		// assign a gray value to the pixel first
		d = disk(r, vec2(-1.1,0.3), 0.4);
		ret = mix(ret, col1, d); // mix the previous color value with
		                         // the new color value according to
		                         // the shape area function.
		                         // at this line, previous color is gray.
		d = disk(r, vec2(-1.3,0.0), 0.4);
		ret = mix(ret, col2, d);
		d = disk(r, vec2(-1.05,-0.3), 0.4); 
		ret = mix(ret, col3, d); // here, previous color can be gray,
		                         // blue or pink.
	} 
	else if(p.x < 2./3.) { // Part II
		// Color addition
		// This is how lights of different colors add up
		// http://en.wikipedia.org/wiki/Additive_color
		ret = black; // start with black pixels
		ret += disk(r, vec2(0.1,0.3), 0.4)*col1; // add the new color
		                                         // to the previous color
		ret += disk(r, vec2(-.1,0.0), 0.4)*col2;
		ret += disk(r, vec2(.15,-0.3), 0.4)*col3;
		// when all components of "ret" becomes equal or higher than 1.0
		// it becomes white.
	} 
	else if(p.x < 3./3.) { // Part III
		// Color substraction
		// This is how dye of different colors add up
		// http://en.wikipedia.org/wiki/Subtractive_color
		ret = white; // start with white
		ret -= disk(r, vec2(1.1,0.3), 0.4)*col1;
		ret -= disk(r, vec2(1.05,0.0), 0.4)* col2;
		ret -= disk(r, vec2(1.35,-0.25), 0.4)* col3;			
		// when all components of "ret" becomes equals or smaller than 0.0
		// it becomes black.
	}
	
	vec3 pixel = ret;
	gl_FragColor = vec4(pixel, 1.0);
}

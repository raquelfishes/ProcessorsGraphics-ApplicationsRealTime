// BUILT-IN FUNCTIONS: MIX
//
// A shader can be created by first constructing individual parts
// and composing them together.
// There are different ways of how to combine different parts.
// In the previous disk example, different disks were drawn on top
// of each other. There was no mixture of layers. When disks
// overlap, only the last one is visible.
//
// Let's learn mixing different data types (in this case vec3's
// representing colors

uniform vec3 iResolution;

void main(void)
{
	vec2 p = vec2(gl_FragCoord.xy / iResolution.xy);
	
	vec3 bgCol = vec3(0.3);
	vec3 col1 = vec3(0.216, 0.471, 0.698); // blue
	vec3 col2 = vec3(1.00, 0.329, 0.298); // yellow
	vec3 col3 = vec3(0.867, 0.910, 0.247); // red
	
	vec3 ret;
	
	// divide the screen into four parts horizontally for different
	// examples
	if(p.x < 1./5.) { // Part I
		// implementation of mix
		float x0 = 0.2; // first item to be mixed
		float x1 = 0.7;  // second item to be mixed
		float m = 0.1; // amount of mix (between 0.0 and 1.0)
		// play with this number
		// m = 0.0 means the output is fully x0
		// m = 1.0 means the output is fully x1
		// 0.0 < m < 1.0 is a linear mixture of x0 and x1
		float val = x0*m + x1*(1.0-m);
		ret = vec3(val);
	} 
	else if(p.x < 2./5.) { // Part II
		// try all possible mix values 
		float x0 = 0.2;
		float x1 = 0.7;
		float m = p.y; 
		float val = x0*(1.0-m) + x1*m;
		ret = vec3(val);		
	} 
	else if(p.x < 3./5.) { // Part III
		// use the mix function
		float x0 = 0.2;
		float x1 = 0.7;
		float m = p.y; 
		float val = mix(x0, x1, m);
		ret = vec3(val);		
	}
	else if(p.x < 4./5.) { // Part IV
		// mix colors instead of numbers
		float m = p.y;
		ret = mix(col1, col2, m);
	}
	else if(p.x < 5./5.) { // Part V
		// combine smoothstep and mix for color transition
		float m = smoothstep(0.5, 0.6, p.y);
		ret = mix(col1, col2, m);
	}
	
	vec3 pixel = ret;
	gl_FragColor = vec4(pixel, 1.0);
}

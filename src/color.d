module color;
@safe:

uint mix(uint a, uint b, float d) {
	ubyte a_r = (a>>16) & 0xff;
	ubyte a_g = (a>> 8) & 0xff;
	ubyte a_b = (a>> 0) & 0xff;
	ubyte b_r = (b>>16) & 0xff;
	ubyte b_g = (b>> 8) & 0xff;
	ubyte b_b = (b>> 0) & 0xff;

	if (d < 0.0) d = 0.0;
	if (d > 1.0) d = 1.0;

	uint R = cast(uint)(b_r * d + a_r * (1.0 - d));
	uint G = cast(uint)(b_g * d + a_g * (1.0 - d));
	uint B = cast(uint)(b_b * d + a_b * (1.0 - d));
	return 0xff000000 | (R<<16) | (G<<8) | (B<<0);
}

static void get_rgb(double c, out uint rgb) {
	// grayscale
	//if (c>1.0) c = 1.0;
	//if (c<0.0) c = 0.0;
	//uint i = cast(uint)(255*c);
	//rgb = 0xff000000 | (i<<16) | (i<<8) | (i<<0);

	// bluish color
	//rgb = 0xff000000;
	//if (c>1.0) c = 1.0;
	//if (c<0.0) c = 0.0;
	//c *= 3;
	//if (c < 1.0) { // back to blue
	//	rgb |= cast(uint)(0xff*c);
	//	return;
	//}
	//rgb = 0xff0000ff;
	//if (c < 2.0)  { // blue to lightblue
	//	c -= 1.0; 
	//	rgb |=  (cast(uint)(0x0000ff00*c) & 0x0000ff00) ; 
	//	return;
	//}
	//rgb = 0xff00ffff; // lightblue to white
	//c -= 2.0;
	//rgb |= cast(uint)(0xff*c)<<16;
	//return;

	// rainbow color blue green yellow red
	//rgb = 0xff000000;
	//if (c>1.0) c = 1.0;
	//if (c<0.0) c = 0.0;
	//c *= 7;

	//if (c < 3.0) { // blue to green
	//	c /= 3;
	//	rgb |= (cast(uint)(0xff*(1.0-c)) | (cast(uint)(0xff*c)<<8));
	//	return;
	//}
	//if (c < 4.0)  { // green to yellow
	//	c -= 3.0; 
	//	if (c>1.0) c = 1.0;
	//	if (c<0.0) c = 0.0;
	//	rgb |= (0xff00 | (cast(uint)(0xff*c)<<16));
	//	return;
	//}
	//if (c < 7.0)  { // yellow to red
	//	c -= 4.0;
	//	c /= 3; 
	//	if (c>1.0) c = 1.0;
	//	if (c<0.0) c = 0.0;
	//	rgb |= (cast(uint)(0xff*(1.0-c))<<8 | 0xff0000);
	//	return;
	//}
	//rgb |= 0xff0000;

	// vidris
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 5;
	import std.math;
	uint ca = cast(uint)floor(c);
	uint cb = ca+1;
	float delta = c-ca;
	uint[6] supports = [ 0xff440154,
	                     0xff414487,
	                     0xff2a788e,
	                     0xff22a884,
	                     0xff7ad151,
	                     0xfffde725 ];

	if (ca > 5) ca = 5;
	if (cb > 5) cb = 5;
	rgb = mix(supports[ca],supports[cb],delta);
	//uint c1 = supports[ci];
	//uint c2 = ci<5?supports[ci+1]:supports[ci];





}

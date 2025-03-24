module color;
@safe:

static void get_rgb(double c, out uint rgb) {
	// grayscale
	//if (c>1.0) c = 1.0;
	//if (c<0.0) c = 0.0;
	//uint i = cast(uint)(255*c);
	//rgb = 0xff000000 | (i<<16) | (i<<8) | (i<<0);

	// bluish color
	rgb = 0xff000000;
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 3;
	if (c < 1.0) { // back to blue
		rgb |= cast(uint)(0xff*c);
		return;
	}
	rgb = 0xff0000ff;
	if (c < 2.0)  { // blue to lightblue
		c -= 1.0; 
		rgb |=  (cast(uint)(0x0000ff00*c) & 0x0000ff00) ; 
		return;
	}
	rgb = 0xff00ffff; // lightblue to white
	c -= 2.0;
	rgb |= cast(uint)(0xff*c)<<16;
	return;

	// rainbow color blue green yellow red
	//rgb = 0xff000000;
	//if (c>1.0) c = 1.0;
	//if (c<0.0) c = 0.0;
	//c *= 3;

	//if (c < 1.0) { // blue to green
	//	rgb |= (cast(uint)(0xff*(1.0-c)) | (cast(uint)(0xff*c)<<8));
	//	return;
	//}
	//if (c < 2.0)  { // green to yellow
	//	c -= 1.0; 
	//	if (c>1.0) c = 1.0;
	//	if (c<0.0) c = 0.0;
	//	rgb |= (0xff00 | (cast(uint)(0xff*c)<<16));
	//	return;
	//}
	//if (c < 3.0)  { // yellow to red
	//	c -= 2.0; 
	//	if (c>1.0) c = 1.0;
	//	if (c<0.0) c = 0.0;
	//	rgb |= (cast(uint)(0xff*(1.0-c))<<8 | 0xff0000);
	//	return;
	//}
	//rgb |= 0xff0000;

}

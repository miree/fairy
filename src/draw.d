module draw;
@safe:

public struct Transform
{
	import std.math;

	int[2] segments; // if the canvas is not in overlay mode, this contains the number of grid segments in each direction

	double[3] min = [-1,-1,-1];
	double[3] max = [ 1, 1, 1];
	double[3] delta = [0,0,0];
	double[3] scale = [1,1,1];
	double[3] min_width = [1e-3, 1e-3, 1e-3];
	double[3] max_width = [1e10, 1e10, 1e10];

	int[2] canvas_width; // in pixels
	bool[3] logscale; 

	long content_idx = -1;

	void set_minmax_width(ulong dim)(double[2] minmax) {
		min_width[dim] = minmax[0];
		max_width[dim] = minmax[1];
	}

	double get_min(ulong dim)()   const pure { return min[dim]-delta[dim];            }
	double get_max(ulong dim)()   const pure { return get_min!dim+get_width!dim;      }
	double get_width(ulong dim)() const pure { return (min[dim]-max[dim])*scale[dim]; }


	void set_minmax(ulong dim)(double[2] minmax) {
		min[dim] = minmax[0];
		max[dim] = minmax[1];
		if (max[dim]-min[dim] < min_width[dim]) {
			double mid = 0.5*(min[dim]+max[dim]);
			min[dim] = mid - 0.5*min_width[dim];
			max[dim] = mid + 0.5*min_width[dim];
		}
		scale[dim] = 1;
		delta[dim] = 0;
	}

	void switch_log2lin(ref double a, ref double b, double max) {
		a = std.math.exp(a);
		b = std.math.exp(b);
		if (b-a > max) b = a+max;
	}
	double minlog(double x, double min=0.1) {
		if (x<=0) x = min;
		return std.math.log(x);
	}
	void switch_lin2log(ref double a, ref double b, double min) {
		a = minlog(a);
		b = minlog(b);
		if (b <= a+min) b=a+min;
	}

	bool set_logscale(ulong dim)(bool l) {
		bool changed = (logscale[dim] != l);
		if (changed &&  l) switch_lin2log(min[dim],max[dim],min_width[dim]);
		if (changed && !l) switch_log2lin(min[dim],max[dim],max_width[dim]);
		logscale[dim] = l;
		return changed;
	}

	double[3] a;
	double[3] b;

	void update_coefficients(int[2] segment, int[2] canvas_w) {
		canvas_width[] = canvas_w[];
		double[2] offset = 1.0 * segment[] * canvas_width[] / segments[];
		double[2] width  = 1.0 * canvas_width[] / segments[];

		b[0] = canvas_width[0] / get_width!0;
		a[0] = offset[0] - b[0] * get_min!0;

		b[1] = - canvas_width[1] / get_width!1;
		a[1] = offset[1] - b[1] * get_max!1;

		b[2] = 1.0 / get_width!2;
		a[2] = - b[2] * get_min!2;
	}

	double get_pixel_width(ulong dim)() pure {
		return (dim?(-1.0):(1.0)) / b[dim];
	}

	double world2canvas(ulong dim)(in double x) const pure {
		return a[dim] + b[dim] * x;
	}
	double world2canvas_delta(ulong dim)(in double dx) const pure {
		return b[dim] * dx;
	}

	double canvas2world(ulong dim)(in double x) const pure {
		return (x - a[dim]) / b[dim];
	}
	double canvas2world_delta(ulong dim)(in double dx) const pure {
		return dx / b[dim];
	}

	double log(ulong dim)(in double x, in double xmin = 0.0) const pure {
		if (log[dim]) return (x>0)?log(x):((xmin>0.0)?log(xmin):get_min!dim);
		return x;
	}
	double exp(ulong dim)(in double x) const pure { 
		if (log[dim]) return std.math.exp(x);
		return x;
	}

	// takes into account the tiling to reduce the x position to the value inside the first tile
	double reduce_canvas(ulong dim)(in double x) const pure {
		double segment_width = canvas_width[dim] / segments[dim];
		int segment = cast(int)(x / segment_width);
		if (segment < 0) segment = 0;
		return x - segment*segment_width;
	}
}

private:
struct TransformationManipulator
{
	Transform *transform;
	double[2] start_canvas;
	double[3] start_world;
	bool active = false;
	bool dim2 = false; // indicate that the manipulation is along dimesion 2 (z-direction)
}
void translate_one_step(ref TransformationManipulator translation, double[2] canvas_start, int[2] canvas_width, double[2] step, double color_key_width) {
	translate_start(translation, canvas_start, canvas_width, color_key_width);
	double[2] canvas_current = canvas_start[] + step[];
	translate_ongoing(translation, canvas_current);
	translate_finish(translation, canvas_current);
}
void translate_start(ref TransformationManipulator translation, double[2] canvas_start, int[2] canvas_width, double color_key_width) {
	with(translation) {
		start_canvas[] = canvas_start[];
		transform.update_coefficients([0,0], canvas_width);
		start_world[0] = transform.canvas2world!0(transform.reduce_canvas!0(canvas_start[0]));
		start_world[1] = transform.canvas2world!1(transform.reduce_canvas!1(canvas_start[1]));
		start_world[2] = transform.canvas2world!2(1.0*(start_world[1] - transform.get_min!1) / transform.get_width!1);
		active = true;
		dim2 = (color_key_width > 0.0) && (start_world[0] > transform.get_min!0 + (1.0 - color_key_width)*transform.get_width!0);
	}
}
void translate_ongoing(ref TransformationManipulator translation, double[2] canvas_current) {
	with(translation) {
		if (dim2) {
			transform.delta[2] = transform.canvas2world_delta!1(canvas_current[1] - start_canvas[1])/transform.get_width!1/transform.b[2];
		} else {
			transform.delta[0] = (canvas_current[0] - start_canvas[0] ) / transform.b[0];
			transform.delta[1] = (canvas_current[1] - start_canvas[1] ) / transform.b[1];
		}
	}
}
void translate_finish(ref TransformationManipulator translation, double[2] canvas_current) {
	with (translation) {
		with (transform) {
			if (dim2) {
				min[2] -= delta[2];
				max[2] -= delta[2];
			} else {
				static foreach(dim; 0..2) {{
					min[dim] -= delta[dim];
					max[dim] -= delta[dim];
				}}
			}
			delta[] = 0;
		}
		active = false;
		dim2 = false;
	}
}
void scale_one_step(ref TransformationManipulator scaler, double[2] canvas_start, int[2] canvas_width, double[2] step, double color_key_width) {
	scale_start(scaler, canvas_start, canvas_width, color_key_width);
	double[2] canvas_current = canvas_start[] + step[];
	scale_ongoing(scaler, canvas_current);
	scale_finish(scaler, canvas_current);
}
void scale_start(ref TransformationManipulator scaler, double[2] canvas_start, int[2] canvas_width, double color_key_width) {
	with(scaler) {
		start_canvas[] = canvas_start[];
		transform.update_coefficients([0,0], canvas_width);
		start_world[0] = transform.canvas2world!0(transform.reduce_canvas!0(canvas_start[0]));
		start_world[1] = transform.canvas2world!1(transform.reduce_canvas!1(canvas_start[1]));
		start_world[2] = transform.canvas2world!2(1.0*(start_world[1] - transform.get_min!1) / transform.get_width!1);
		active = true;
		dim2 = (color_key_width > 0.0) && (start_world[0] > transform.get_min!0 + (1.0 - color_key_width)*transform.get_width!0);
	}
}
void scale_ongoing(ref TransformationManipulator scaler, double[2] canvas_current) {
	with(scaler) {
		import std.math;
		if (dim2) {
			double scale_distance = canvas_current[1] - scaler.start_canvas[1];
			transform.scale[2] = std.math.exp(scale_distance/100.0);
			double new_min = scaler.start_world[2] - transform.scale[2]*(scaler.start_world[2] - transform.min[2]);
			transform.delta[2] = transform.min[2] - new_min;
		} else {
			static foreach(dim; 0..2) {{
				double scale_distance = canvas_current[dim] - scaler.start_canvas[dim];
				if (dim == 0) scale_distance *= -1;
				transform.scale[dim] = std.math.exp(scale_distance/100.0);
				if (transform.get_width!dim < transform.min_width[dim]) transform.scale[dim] = transform.min_width[dim] / (transform.max[dim]-transform.min[dim]);
				if (transform.get_width!dim > transform.max_width[dim]) transform.scale[dim] = transform.max_width[dim] / (transform.max[dim]-transform.min[dim]);
				double new_min = scaler.start_world[dim] - transform.scale[dim]*(scaler.start_world[dim] - transform.min[dim]);
				transform.delta[dim] = transform.min[dim] - new_min;
			}}
		}
	}	
}
void scale_finish(ref TransformationManipulator scaler, double[2] canvas_current) {
	with(scaler) {
		with(transform) {
			if (dim2) {
				double width = get_width!2;
				min[2] -= delta[2];
				max[2]  = min[2] + width;
			} else {
				static foreach(dim; 0..2) {{
					double width = get_width!dim;
					min[dim] -= delta[dim];
					max[dim]  = min[dim] + width;
				}}
			}
			scale[] = 1.0;
			delta[] = 0.0;
		}
		active = false;
		dim2 = false;
	}
}


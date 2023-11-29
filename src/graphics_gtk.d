module graphics_gtk;
@trusted:

version(gtk3) {
	pragma(lib, "gtkd-3");
} 
version(gtk4) {
	pragma(lib, "gtkd-4");
} 


import graphics;

class GtkGui : Gui {

	import gtk.Application;
	import gtk.ApplicationWindow;
	import glib.Timeout;

	Timeout refresh_timeout;
	Application application = null;

	static MainWindow[string] main_windows;

	override void add_window(string name, ref CanvasProperties canvas) {
		main_windows[name] = new MainWindow(name, &canvas, application);
	}
	override void close_window(string name) {
		//import std.stdio;
		//writeln("close window ", name , "     all windows ", main_windows);
		if (name in main_windows) {
			main_windows[name].close();
			main_windows.remove(name);
		}
	}
	override void redraw_window(string name) {
		if (name in main_windows) {
			main_windows[name].plot_widget.plot_area.need_redraw();
		}
	}
	override void save_window(string name) { // copy window properties to canvas
		auto window = main_windows[name];
		GdkRectangle rect;
		window.window_toplevel_box.getAllocation(rect);
		window.canvas.width  = rect.width;
		version(gtk4) {
			window.canvas.height = rect.height+56;
		}
		version(gtk3) {
			window.canvas.height = rect.height;
			int x,y;
			window.getPosition(x, y);
			window.canvas.xpos = x;
			window.canvas.ypos = y;
		}
	}
	override void remove_item(string name) {
		foreach(window; main_windows) {
			window.item_view.removeItem(name);
		}
	}
	override void add_item(string name) {
		foreach(window; main_windows) {
			window.item_view.addItem(name, null);
		}
	}
	override void update_from_canvas(string name) {
		if (name in main_windows) {
			main_windows[name].update_from_canvas(); 
		}
	}

	override void loop() {
		// setup the application instance only if it is not already running
		if (application !is null) {
			import std.stdio;
			throw new Exception("Application already running");
			return;
		}

		// start it as NON_UNIQUE application. That means multiple independent 
		// instances of this application can be started.
		import app; 
		application = new gtk.Application.Application("de.risingedge.fairy", GApplicationFlags.NON_UNIQUE);

		import gio.Application;
		application.addOnActivate(
			delegate void(gio.Application.Application app) { 
				import fairy;
				// this prevents the application 
				//  from terminating if no GUI is pesent
				app.hold(); 
				immutable ulong refresh_period_ms = 100;
				refresh_timeout = new Timeout(refresh_period_ms, delegate bool() 
				{
					if(!fairy.running) application.quit();

					if (fairy.iterate(0)) {
						import std.stdio;
						stdout.write("fairy> ");
						stdout.flush();
					}
					foreach(name, window; main_windows) {
						import ui;
						if (window.canvas.autorefresh) winrefresh(window.name);
					}
					return true;
				});

				foreach(name, ref canvas; session.windows) {
					add_window(name, canvas);
				}
			}
		);
		application.addOnShutdown(
			delegate void(gio.Application.Application app) {
				foreach(name; main_windows.byKey) save_window(name);
				import std.stdio;
				stderr.writeln("Application shutdown");
			}
		);

		string[] applicationArgs;
		auto result = application.run(applicationArgs);
		import std.stdio;
		writeln();
	}
}

// some gtk3/gtk4 compatibility/convenience functions
version(gtk3) 
{
	import gtk.Widget;
	void setChild(ParentWidget, ChildWidget)(ParentWidget p, ChildWidget ch) {
		p.add(ch);
	}

	// get int and string out of a treestore iterator
	import gtk.TreeStore, gtk.TreeIter;
	int getInt(TreeStore store , TreeIter iter, int column) {
		return store.getValue(iter,column).getInt();
	}
	string getString(TreeStore store , TreeIter iter, int column) {
		return store.getValue(iter,column).getString();
	}
} 
version(gtk4) {
	// get int and string out of a treestore iterator
	import gtk.TreeStore, gtk.TreeIter, gobject.Value;
	int getInt(TreeStore store , TreeIter iter, int column) {
		auto out_value = new Value;
		store.getValue(iter, column, out_value);
		return out_value.get!int();
	}
	string getString(TreeStore store , TreeIter iter, int column) {
		auto out_value = new Value;
		store.getValue(iter, column, out_value);
		return out_value.get!string();
	}
}


string fixWindowsPaths(string path) {
	version(Windows){
		string result;
		foreach(ref ch; path) {
			if (ch == '\\') {
				result ~= '/';
			} else {
				result ~= ch;
			}
		}
		return result;
	} else {
		return path;
	}
}

import gio.SimpleAction;
import glib.Variant;

import gtk.Application;
import gtk.ApplicationWindow;
class MainWindow : ApplicationWindow
{
private:
	CanvasProperties *canvas;

	import gtk.Button;
	import gtk.HeaderBar;
	import gtk.Paned;
	import gtk.Widget;
	import gtk.Box;
	import gtk.Label;
	import gtk.Button;
	import gtk.ScrolledWindow;
	import gtk.PopoverMenu;
	import gtk.Popover;
	//version(gtk3) {
		import gio.Menu;
		import gio.MenuItem;
	//}
	//version(gtk4) {
	//	import gio.MenuItem;
	//}

	const int min_width  = 600;
	const int min_height = 400;
	int width  = 640;
	int height = 400;

	static int windowIndexCtr;
	string name;

	Box window_toplevel_box;
	HeaderBar header_bar;
		Button open_menu;
			Menu menu_top;
				version(gtk3) { Popover menu_popover; }
				version(gtk4) { PopoverMenu menu_popover; }
		Button open_soundscope;
		Label  header_title;
	Paned workspace;
		ScrolledWindow item_view_scrolled_window;
			ItemView item_view;
		PlotWidget plot_widget;

	SimpleAction new_window;
	SimpleAction save_session_as;
	SimpleAction open_session;
	SimpleAction quit_program;
	SimpleAction expand_all_selected;
	SimpleAction remove_all_selected;
	SimpleAction show_all_selected;
	SimpleAction show_all_recursive;
	SimpleAction hide_all_selected;
	SimpleAction hide_all_recursive;
	SimpleAction reset_all_selected;
	SimpleAction reset_all_recursive;

	import gtk.EventControllerKey;
	EventControllerKey event_controller_key;

	import glib.Timeout;
	Timeout open_session_timeout;

public:

	void update_from_canvas() {
		assert(item_view !is null);
		item_view.sync_with_session();
		item_view.sync_with_canvas(canvas);
		plot_widget.sync_with_canvas(canvas);
	}

	this(string window_name, CanvasProperties *canvas_properties, Application application) {
		canvas = canvas_properties;
		super(application);
		setDecorated(true);
		// check arguments
		import std.algorithm;
		width  = (canvas_properties.width >0)?max(canvas_properties.width , min_width):min_width;
		height = (canvas_properties.height>0)?max(canvas_properties.height, min_height):min_height;
		version(gtk3) {
			move(canvas.xpos, canvas.ypos);
		}

		import ui;

		new_window = new SimpleAction("new_window", null);
		new_window.addOnActivate(delegate(Variant var, SimpleAction action) {
			for (int i = 0; i < 100;++i) {
				import std.conv;
				try {
					ui.win("window" ~ i.to!string);
					break;
				} catch(Exception e) {
					// window with this name was probably already present
				}
			}
		});
		addAction(new_window);

		save_session_as = new SimpleAction("save_session_as", null);
		save_session_as.addOnActivate(delegate(Variant var, SimpleAction action) {
			import gtk.FileChooserDialog, gtk.Dialog, gtk.FileFilter; 
			auto dialog = new FileChooserDialog("choose session name", /*parent_window=*/this, FileChooserAction.SAVE);
				auto session_filter = new FileFilter; 
				     session_filter.addPattern("*.session"); 
				     session_filter.setName("*.session");
				dialog.addFilter(session_filter);
				dialog.setCreateFolders(true);
				dialog.addOnResponse((int response, Dialog dialog) {
					if (response == ResponseType.OK) {
						import std.algorithm, std.path, std.file, std.string, std.stdio;
						auto cwd = getcwd().fixWindowsPaths;
						version(gtk3) {
							auto filename = (cast(FileChooserDialog)dialog).getFilenames().toArray!string[0].fixWindowsPaths().chompPrefix(cwd~"/");
						}
						version(gtk4) {
							auto filename = (cast(FileChooserDialog)dialog).getFile().getPath().fixWindowsPaths().chompPrefix(cwd~"/");
							import std.stdio; writeln("filename=", filename);
						}
						if (filename.endsWith(".session")) { filename = filename[0..$-8]; }
						import ui;
						session_save(filename);
						//runningSession.rename(filename); 
						//runningSession.writeToFile();
						//notifySessionChange();
						dialog.close();
					} 
					if (response == ResponseType.CANCEL) { dialog.close(); }
				});
			dialog.show();
		});
		addAction(save_session_as);

		open_session = new SimpleAction("open_session", null);
		open_session.addOnActivate(delegate(Variant var, SimpleAction action) {
			import gtk.FileChooserDialog, gtk.Dialog, gtk.FileFilter; 
			auto dialog = new FileChooserDialog("choose session file", /*parent_window=*/this, FileChooserAction.OPEN 
												// following is only needed when labels and actions are needed
				                               //,["Open",              "Cancel"           ] 
				                               //,[ResponseType.ACCEPT, ResponseType.CANCEL]
				                               );
				auto session_filter = new FileFilter; 
				     session_filter.addPattern("*.session"); 
				     session_filter.setName("*.session");
				dialog.addFilter(session_filter);
				dialog.addOnResponse((int response, Dialog dialog) {
					if (response == ResponseType.OK) {
						import std.algorithm, std.path, std.file, std.string, std.stdio;
						auto cwd = getcwd().fixWindowsPaths;
						version(gtk3) {
							auto filename = (cast(FileChooserDialog)dialog).getFilenames().toArray!string[0].fixWindowsPaths().chompPrefix(cwd~"/");
						}
						version(gtk4) {
							auto filename = (cast(FileChooserDialog)dialog).getFile().getPath().fixWindowsPaths().chompPrefix(cwd~"/");
							import std.stdio; writeln("filename=", filename);
						}
						if (filename.endsWith(".session")) { filename = filename[0..$-8]; }
						// execute the command with a short delay to make sure the dialog window is closed before the action is executed
						open_session_timeout = new Timeout(100, delegate bool() {
							import ui;
							ui.session_open(filename);
							return false;
						});
						dialog.close();
					} 
					if (response == ResponseType.CANCEL) dialog.close(); 
				});
			dialog.show();

		});
		addAction(open_session);

		quit_program = new SimpleAction("quit", null);
		quit_program.addOnActivate(delegate(Variant var, SimpleAction action) {
			import ui;
			ui.quit();
		});
		addAction(quit_program);

		expand_all_selected = new SimpleAction("expand_all", null);
		expand_all_selected.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.expand_all_selected();
		});
		addAction(expand_all_selected);

		show_all_selected = new SimpleAction("show_all_selected", null);
		show_all_selected.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.show_all_selected();
		});
		addAction(show_all_selected);

		show_all_recursive = new SimpleAction("show_all_recursive", null);
		show_all_recursive.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.show_all_recursive();
		});
		addAction(show_all_recursive);

		hide_all_selected = new SimpleAction("hide_all_selected", null);
		hide_all_selected.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.hide_all_selected();
		});
		addAction(hide_all_selected);

		hide_all_recursive = new SimpleAction("hide_all_recursive", null);
		hide_all_recursive.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.hide_all_recursive();
		});
		addAction(hide_all_recursive);

		reset_all_selected = new SimpleAction("reset_all_selected", null);
		reset_all_selected.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.reset_all_selected();
		});
		addAction(reset_all_selected);

		reset_all_recursive = new SimpleAction("reset_all_recursive", null);
		reset_all_recursive.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.reset_all_recursive();
		});
		addAction(reset_all_recursive);

		remove_all_selected = new SimpleAction("remove_selected", null);
		remove_all_selected.addOnActivate(delegate(Variant var, SimpleAction action) {
			item_view.remove_all_selected();
		});
		addAction(remove_all_selected);


		name = window_name;

		//import app;
		setTitle("fairy - " ~ window_name);

		// set window size
		import gdk.Display;
		import std.algorithm;
		setDefaultSize(canvas_properties.width, canvas_properties.height);

		header_bar = new HeaderBar;
		// add title to header bar
		header_title = new Label("fairy - " ~ window_name);
		version(gtk4) { 
			header_bar.setTitleWidget(header_title); 
			header_bar.setShowTitleButtons(false); // to match gtk3 behavior
		}
		version(gtk3) { 
			header_bar.setTitle("fairy - " ~ window_name); 
		}

		// add menu and other buttons to title bar
		open_menu    = new Button();
		//close_window = new Button();
		version(gtk3) {
			import gtk.Image, gtk.c.types;
			auto open_image = new Image;
			open_image.setFromIconName("open-menu-symbolic", IconSize.LARGE_TOOLBAR);
			open_menu.setImage(open_image);
			header_bar.setShowCloseButton(true);		
		}
		version(gtk4) { 
			open_menu.setIconName("open-menu-symbolic"); 
			header_bar.setShowTitleButtons(true);
		}

		//header_bar.packEnd(close_window);
		header_bar.packStart(open_menu);

		application.setAccelsForAction("win.new_window", ["<Control>n"]);
		application.setAccelsForAction("win.open_session", ["<Control>o"]);

		menu_top = new Menu;
		menu_top.append("new window",      "win.new_window");
		menu_top.append("save session as", "win.save_session_as");
		menu_top.append("open session",    "win.open_session");
		menu_top.append("quit",            "win.quit");
		version(gtk3) { 
			menu_popover = new Popover(open_menu); 
			menu_popover.bindModel(menu_top, null);
			//menu_popover.setHasArrow(false); // how to remove the arrow?
		}
		version(gtk4) { 
			menu_popover = new PopoverMenu(menu_top); 
			menu_popover.setParent(open_menu);
			//menu_popover.setHasArrow(false);
		}
		menu_popover.setPosition(PositionType.BOTTOM);
		open_menu.addOnClicked((Button button) => menu_popover.setVisible(true));

		//open_soundscope = new Button("soundscope");
		//open_soundscope.addOnClicked(delegate(Button button) {
		//	import soundscope;
		//	new SoundScopeWindow(application);
		//});
		//header_bar.packStart(open_soundscope);


		window_toplevel_box = new Box(GtkOrientation.VERTICAL,0);


		plot_widget = new PlotWidget(canvas_properties, window_name);//(area, window_name);
		plot_widget.setHexpand(true);

		item_view = new ItemView(plot_widget, this);

		item_view.sync_with_session();
		item_view.sync_with_canvas(canvas);

		item_view_scrolled_window = new ScrolledWindow();
		item_view_scrolled_window.setPropagateNaturalWidth(true);
		item_view_scrolled_window.setPropagateNaturalHeight(true);
		item_view_scrolled_window.setChild(item_view);

		workspace = new Paned(GtkOrientation.HORIZONTAL);
		workspace.setPosition(200);
		version (gtk3) {
			workspace.add(item_view_scrolled_window, plot_widget);
			//add(workspace);
		} 
		version(gtk4) {
			workspace.setStartChild(item_view_scrolled_window);
			workspace.setResizeStartChild(false);
			workspace.setShrinkStartChild(true);
			workspace.setEndChild(plot_widget);
			workspace.setResizeEndChild(true);
			workspace.setShrinkEndChild(false);
		}
		version(gtk3) {
			addOnHide((Widget) {
				import fairy;
				try {
					if ((name in GtkGui.main_windows) !is null) GtkGui.main_windows.remove(name);
					fairy.session.close_window(name);
				} catch (Exception e) {
					// nothing
					// we land here if the close was executed from command line 
					// then fairy.sesssion.close_window is executed once called from command line
					// and again if the window gets a Destroy-notification
				}
			});
		}
		version(gtk4) {
			setHideOnClose(true);
			addOnHide((Widget) {
				import fairy;
				try {
					if ((name in GtkGui.main_windows) !is null) GtkGui.main_windows.remove(name);
					fairy.session.close_window(name);
				} catch (Exception e) {
					// nothing
					// we land here if the close was executed from command line 
					// then fairy.sesssion.close_window is executed once called from command line
					// and again if the window gets a Hide-notification
				}
			});
		}
		addOnRealize((Widget) {
			version (gtk3) {
				import std.stdio;
				getDefaultSize(width,height);
			} 
			version(gtk4) {
				import std.stdio;
				bool mdrawFuncaximized = isMaximized();
				getDefaultSize(width,height);
				import gdk.Display, gdk.MonitorGdk;
				auto monitors = Display.getDefault().getMonitors();
				//writeln("monitors size=", monitors.getNItems());
				auto monitor = new MonitorGdk( cast(GdkMonitor*)monitors.getItem(0) );
				GdkRectangle rect;
				monitor.getGeometry(rect);
				//writeln("rect ", rect);
			}		
		});

		version(gtk3) {
			addOnKeyPress(delegate bool(GdkEventKey* e, Widget w) { // the action to perform if that menu entry is selected
				handle_keyboard_shortcut(e.keyval);
				return true; // don't propagate
				//return false; // propagate
			});
		}
		version(gtk4) {
			event_controller_key = new EventControllerKey();
			event_controller_key.addOnKeyPressed(delegate bool(uint keyval, uint keycode, GdkModifierType mod, EventControllerKey controller) {
				handle_keyboard_shortcut(keyval);
				return true; // don't propagate further				
			});
			this.addController(event_controller_key);
			
			item_view.setFocusable(false);  // prevent other widgets from stealing the key press events 
			plot_widget.setFocusable(false);// (see https://docs.gtk.org/gtk4/input-handling.html)

		}

		window_toplevel_box.append(header_bar);
		window_toplevel_box.append(workspace);
		this.setChild(window_toplevel_box);

		setSizeRequest(-1,-1);
		present();


		version(gtk3){ 
			showAll();
		}
	}

	void handle_keyboard_shortcut(uint keyval) {
		import ui;
		switch(keyval) {
			case '1': .. case '9': plot_widget.spin_n_columns.setValue(keyval-'0'); break;
			case 'u': ui.winrefresh(name);                                 break;
			case 'p': ui.winpoll(name);                                    break;
			case 'q': ui.winzoom(name,1*1.2);                              break;
			case 'e': ui.winzoom(name,1/1.1666666666);                     break;
			case 'a': ui.winmove(name,'x',-0.2);                           break;
			case 'd': ui.winmove(name,'x',+0.2);                           break;
			case 's': ui.winmove(name,'y',-0.2);                           break;
			case 'w': ui.winmove(name,'y',+0.2);                           break;
			case 'o': ui.overlay(name);                                    break;
			case 'b': ui.colorbar(name);                                   break;
			case 'c': plot_widget.radio_colmajor.setActive(true);          break;
			case 'r': plot_widget.radio_rowmajor.setActive(true);          break;
			case 'z': ui.autoscale(name, 'z', "toggle");                   break;
			case 'x': ui.autoscale(name, 'x', "toggle");                   break;
			case 'y': ui.autoscale(name, 'y', "toggle");                   break;
			case 'l': ui.logscale (name, canvas.dim==2?'z':'y', "toggle"); break;
			case 'f': ui.winfit(name);                                     break;
			default: {}
		}
	}


}

import gtk.TreeStore, gtk.TreeView, gtk.TreeIter;

class ItemView : TreeView {

	version(gtk4) { // GtkD-3 has this as convenience function (not a genuine gtk function) that is missing in GtkD-4
		TreeIter[] getSelectedIters() {
			import gtk.TreePath;
			TreeIter[] iters;
			auto selection = getSelection();
			TreeModelIF model = getModel();
			auto paths = selection.getSelectedRows(model).toArray!TreePath;
			TreeIter iter;
			foreach ( TreePath p; paths ) {
				if ( model.getIter(iter,p) ) {
					iters ~= iter;
				}
			}
			return iters;
		}
	}

	PlotWidget plotwidget;
	MainWindow main_window;

	enum {
		COLUMN_NAME,
		COLUMN_FULLNAME,
		COLUMN_IS_ITEM,    // if this is true, there is an item under that fullname, otherwise it is just a folder
		COLUMN_VISUALIZED, // the checkbox to visualize the item (or recursively all items in the folder)
	}

	TreeStore treestore;


	version(gtk3) {
		import gtk.Menu, gtk.MenuItem;
		Menu popup_menu;
	}
	version(gtk4) {
		import gtk.PopoverMenu, gtk.Popover;
		import gio.Menu, gio.MenuItem;
		import gtk.GestureClick;
		GestureClick right_click;
		Menu menu;
		PopoverMenu popup_menu;
	}

	void expand_all_selected() {
		foreach(selected_iter; getSelectedIters()) {
			this.expandRow(treestore.getPath(selected_iter), true);
		}
	}
	void remove_all_selected() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			names ~= treestore.getString(selected_iter, COLUMN_FULLNAME);
		}
		foreach(name; names) {
			try {
				import ui;
				if (name !is null) ui.rm(name);
			} catch (Exception e) {
				import std.stdio;
				writeln("cannot remove " ~ name ~": " ~ e.msg);
			}
		}
	}
	void show_all_selected() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			names ~= treestore.getString(selected_iter, COLUMN_FULLNAME);
		}
		foreach(name; names) {
			try {
				import ui;
				if (name !is null) ui.show(name, main_window.name);
			} catch (Exception e) {
				import std.stdio;
				writeln("cannot show " ~ name ~": " ~ e.msg);
			}
		}
	}
	void show_all_recursive() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			bool active = true;
			iterate_children_depth_first(&active, treestore, selected_iter, 0,
				(bool* force_active, string full_name, TreeStore treestore, TreeIter iter, int nothing) { 
					switch_iter(treestore, iter, plotwidget, force_active);
				});
		}
	}

	void hide_all_selected() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			names ~= treestore.getString(selected_iter, COLUMN_FULLNAME);
		}
		foreach(name; names) {
			try {
				import ui;
				if (name !is null) ui.show(name, main_window.name, "false");
			} catch (Exception e) {
				import std.stdio;
				writeln("cannot show " ~ name ~": " ~ e.msg);
			}
		}
	}
	void hide_all_recursive() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			bool active = false;
			iterate_children_depth_first(&active, treestore, selected_iter, 0,
				(bool* force_active, string full_name, TreeStore treestore, TreeIter iter, int nothing) { 
					switch_iter(treestore, iter, plotwidget, force_active);
				});
		}
	}

	void reset_all_selected() {
		string[] names; 
		foreach(selected_iter; getSelectedIters()) {
			names ~= treestore.getString(selected_iter, COLUMN_FULLNAME);
		}
		foreach(name; names) {
			try {
				import ui;
				if (name !is null) ui.reset(name);
			} catch (Exception e) {
				import std.stdio;
				writeln("cannot show " ~ name ~": " ~ e.msg);
			}
		}
	}
	void reset_all_recursive() {
		import ui;
		foreach(selected_iter; getSelectedIters()) {
			string full_name = treestore.getString(selected_iter, COLUMN_FULLNAME);
			if (full_name !is null && full_name.length > 0) {
				try { if (full_name !is null) ui.reset(full_name); } catch (Exception e) { }
			} 
			iterate_children_depth_first(null, treestore, selected_iter, 0,
				(bool* dummy, string full_name, TreeStore treestore, TreeIter iter, int nothing) {
					try { if (full_name !is null) ui.reset(full_name); } catch (Exception e) { }
				});
		}
	}


	this(PlotWidget pw, MainWindow mainwindow) {
		plotwidget = pw;
		main_window = mainwindow;
	                               // NAME        FULLNAME        IS_ITEM    VISUALIZED
		treestore = new TreeStore([ GType.STRING , GType.STRING , GType.INT , GType.INT ]);
		super(treestore);
		setVexpand(true);
		import gtk.TreeViewColumn, gtk.CellRendererText, gtk.CellRendererToggle;
		auto text_renderer = new CellRendererText;
		auto color_renderer = new CellRendererText;
		auto toggle_renderer = new CellRendererToggle;
		toggle_renderer.addOnToggled( delegate void(string p, CellRendererToggle crt){
			import gtk.TreePath, gtk.TreeIter;
			import std.typecons;
			auto path = scoped!TreePath(p); // p is something like "2:4:1"
			version(gtk3) {
				auto iter = scoped!TreeIter(treestore, path);
			} else {
				TreeIter iter;
				treestore.getIter(iter, path);
			}
			// recursively toggle children (only if iter is not an acutal item)
			auto is_item = treestore.getInt(iter, COLUMN_IS_ITEM); // gtk3/gtk4 compatibility/convenience function
			bool active = switch_iter(treestore, iter, plotwidget); 
			if (!is_item) { // only recurse for non-items
				iterate_children_depth_first(&active, treestore, iter, 0,
					(bool* force_active, string full_name, TreeStore treestore, TreeIter iter, int nothing) { 
						switch_iter(treestore, iter, plotwidget, force_active);
					});
			}

			// check if a parent has to be toggled
			import std.array;
			auto path_parts = p.split(':');
			while (path_parts.length > 1) {
				path_parts = path_parts[0..$-1];
				p = path_parts.join(':');
				path = scoped!TreePath(p);
				version(gtk3) {
					iter = scoped!TreeIter(treestore, path);
				} else {
					treestore.getIter(iter, path);
				}
				is_item = treestore.getInt(iter, COLUMN_IS_ITEM); // gtk3/gtk4 compatibility/convenience function
				if (!is_item) {
					struct Children {
						bool all_set = true;
						bool none_set = true;
					}
					Children children;
					iterate_children_depth_first(&active, treestore, iter, &children, 
						(bool* force_active, string full_name, TreeStore treestore, TreeIter iter, Children *children) { 
							auto child_active = treestore.getInt(iter, COLUMN_VISUALIZED); 
							if (child_active) children.none_set = false;
							if (!child_active) children.all_set = false;
					});
					if (children.none_set) {
						version (gtk3) {
							treestore.setValue(iter, COLUMN_VISUALIZED, 0);
						} 
						version (gtk4) {
							import gobject.Value, std.typecons;
							treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(0));
						}
					}
					if (children.all_set) {
						version (gtk3) {
							treestore.setValue(iter, COLUMN_VISUALIZED, 1);
						} 
						version (gtk4) {
							import gobject.Value, std.typecons;
							treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(1));
						}
					}
				}
			}
		});


		appendColumn(new TreeViewColumn("Name", text_renderer,   "text",   COLUMN_NAME));
		appendColumn(new TreeViewColumn("Show", toggle_renderer, "active", COLUMN_VISUALIZED));
		getSelection().setMode(GtkSelectionMode.MULTIPLE);


		version(gtk3) {
			popup_menu = new Menu;
			popup_menu.append( new MenuItem( (m) => expand_all_selected(), "expand recursive", "recursively expand all child items" ));
			popup_menu.append( new MenuItem( (m) => show_all_recursive(),  "show recursive", "show selected items and their children"));
			popup_menu.append( new MenuItem( (m) => hide_all_recursive(),  "hide recursive", "hide selected items and their children"));
			popup_menu.append( new MenuItem( (m) => reset_all_recursive(), "reset recursive", "reset selected items and their children"));
			popup_menu.append( new MenuItem( (m) => show_all_selected(),   "show", "show selected items"));
			popup_menu.append( new MenuItem( (m) => hide_all_selected(),   "hide", "hide only selected items"));
			popup_menu.append( new MenuItem( (m) => reset_all_selected(),  "reset", "reset selected items and"));
			popup_menu.append( new MenuItem( (m) => remove_all_selected(), "remove", "remove selected items"));
			addOnButtonPress(
				delegate bool(GdkEventButton* e, Widget w) {
					if (e.button == 3)	{
						popup_menu.popup(e.button, e.time);
						popup_menu.showAll(); 
						return true;
					}
					w.onButtonPressEvent(e); 
					return false;
				} 
			);
		}

		version(gtk4) {
			menu = new Menu;
			menu.append("expand recursive", "win.expand_all");
			menu.append("show recursive",   "win.show_all_recursive");
			menu.append("hide recursive",   "win.hide_all_recursive");
			menu.append("reset recursive",  "win.reset_all_recursive");
			menu.append("show",             "win.show_all_selected");
			menu.append("hide",             "win.hide_all_selected");
			menu.append("reset",            "win.reset_all_selected");
			menu.append("remove",           "win.remove_selected");

			popup_menu = new PopoverMenu(menu); 
			right_click = new GestureClick;
			addController(right_click);
			right_click.setButton(BUTTON_SECONDARY); 
			right_click.addOnPressed(delegate void(int nPress, double x, double y, GestureClick g) {
				import std.stdio; writeln("right click");
				auto w = cast(ItemView)g.getWidget();
				w.popup_menu.setParent(w);
				auto rect = GdkRectangle(cast(int)x, cast(int)y, 4,4);
				w.popup_menu.setPointingTo(&rect);
				w.popup_menu.setHasArrow(false);
				w.popup_menu.setPosition(PositionType.BOTTOM);
				w.popup_menu.setVisible(true);
			});
		}
	}

	void show_visualizer(string item_name) {
		import gobject.Value, std.typecons;
		TreeIter iter = find_iter_for_itemname(item_name, treestore);
		treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(1));
		fix_parent_checkboxes(iter);
	}
	void hide_visualizer(string item_name) {
		import gobject.Value, std.typecons;
		TreeIter iter = find_iter_for_itemname(item_name, treestore);
		treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(0));
		fix_parent_checkboxes(iter);
	}
	void fix_parent_checkboxes(TreeIter iterator) {
		import gobject.Value, std.typecons, std.stdio;
		TreeIter parent = null;
		if (treestore.iterParent(parent, iterator)) {
			//writeln("parent iter found");
			if (!treestore.getInt(parent, COLUMN_IS_ITEM)) {
				//writeln("parent is no item");
				int n_children = treestore.iterNChildren(parent);
				TreeIter iter = null;
				int count = 0;
				bool all_children_visualized = true;
				bool no_child_visualized = true;
				foreach (n ; 0..n_children) {
					if (treestore.iterNthChild(iter, parent, n)) {
						if (treestore.getInt(iter, COLUMN_VISUALIZED) == 0) {
							all_children_visualized = false;
						} else {
							no_child_visualized = false;
						}
					}
				}
				if (all_children_visualized) {
					treestore.setValue(parent, COLUMN_VISUALIZED, scoped!Value(1));
				}
				if (no_child_visualized) {
					treestore.setValue(parent, COLUMN_VISUALIZED, scoped!Value(0));
				}
			}
		}
	}



	// helper function to send visualizers to the plotwidget and update the checkbox in the treeview
	bool switch_iter(TreeStore treestore, TreeIter iter, PlotWidget plotwidget, bool* force_active = null) {
		//import app, std.stdio;

		auto active   = treestore.getInt(iter, COLUMN_VISUALIZED); // use a gtk3/gtk4 compatibility/convenience function
		auto fullname = treestore.getString(iter, COLUMN_FULLNAME); // use a gtk3/gtk4 compatibility/convenience function
		// if force_active value is given use it to override the value from the row
		if (force_active is null) { active = !active; } 
		else                      { active = *force_active; }

		version (gtk3) {
			treestore.setValue(iter, COLUMN_VISUALIZED, active);
		} else {
			import gobject.Value, std.typecons;
			treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(active));
		}
		if (treestore.getInt(iter, COLUMN_IS_ITEM)) {
			//import std.stdio;
			//writeln(active, " " , fullname);
			import ui;
			ui.show(fullname, main_window.name, active?"true":"false");
		}
		//// add or remove the visualizer from plotaera
		//auto visualizer = runningSession.getVisualizerForItemName(fullname);
		//if (active) { plotwidget.addVisualizer(fullname, visualizer); }
		//else        { plotwidget.removeVisualizer(fullname); }
		// return the new state of the checkbox
		return cast(bool)active;
	}



	import item;

	void sync_with_session(bool clear = false)
	{	
		if (clear) { treestore.clear(); }
		import fairy;
		foreach (itemname, item; session.items) {
			addItem(itemname, item.item);
		}
	}


	void addItem(string itemname, Item item) {
		import std.array;
		// fix the 'empty root problem' in Linux where the root folder is just the empty string
		string[] parts = itemname.split("/");
		if (parts[0] == "") parts[0] ~= "/";
		// fixing done
		add_item_(itemname, parts, item);
	}

	void add_item_(string fullname, string[] parts, const(Item) item, TreeIter parent = null) 
	{
		import gobject.Value, std.typecons;
		void set_iter(TreeIter iter, string fullname, string[] parts) {
			// only rows that really refer to items get a fullname assigned // todo: is this desirable?
			if (parts.length > 1) {	fullname = null; }
			int is_item = (parts.length==1);
			// this way of setting the values only works for the string types
			//treestore.set(iter, [COLUMN_FULLNAME, COLUMN_COLOR_TEXT, COLUMN_NAME,   COLUMN_TYPE      ], 
			//	                 [fullname,        (is_item)?"⬤":"", parts[0],      item.typeString()]);
			treestore.setValue(iter, COLUMN_NAME,       scoped!Value(parts[0]));
			treestore.setValue(iter, COLUMN_FULLNAME,   scoped!Value(fullname));
			treestore.setValue(iter, COLUMN_IS_ITEM,    scoped!Value(is_item));
			treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(0));
		}

		//iterate all children of the root nodes and try to find one with the correct prefix of the given fullname
		import std.stdio;
		assert(parts.length > 0);
		int n_children = treestore.iterNChildren(parent);
		TreeIter iter = null;
		TreeIter iter_first, iter_after; // for sorted insertion
		foreach (n ; 0..n_children) {
			if (treestore.iterNthChild(iter, parent, n)) {
				auto name = treestore.getString(iter, COLUMN_NAME); // gtk3/gtk4 compatibility/convenience function
				if (n == 0)          iter_first = iter;
				if (name < parts[0]) iter_after  = iter;
				if (name == parts[0]) {
					//writeln("names match: ", name);
					if (parts.length == 1) { return set_iter(iter, fullname, parts); }    // set the iterator (end of recursion)
					else                   { return add_item_(fullname, parts[1..$], item, iter); } // recurse down
				}
			}
		}
		// not found, add new row and sort it to the right place
		treestore.append(iter, parent);
		if (iter_after  !is null) treestore.moveAfter(iter, iter_after);
		else                      treestore.moveBefore(iter, iter_first);
		// set new iterator contents
		set_iter(iter, fullname, parts);
		if (parts.length > 1) {
			add_item_(fullname, parts[1..$], item, iter);
		}
	}

	import gtk.TreeModelIF, gtk.TreeIter, gtk.TreeStore;
	int iterate_children_depth_first(F,D)(bool* select, TreeStore treestore, TreeIter parent, D data, F func) {
		int n_children = treestore.iterNChildren(parent);
		TreeIter iter = null;
		int count = 0;
		foreach (n ; 0..n_children) {
			if (treestore.iterNthChild(iter, parent, n)) {
				if( treestore.iterNChildren(parent) ) {
					count += iterate_children_depth_first!(F,D)(select, treestore, iter, data, func);
				}
				auto fullname = treestore.getString(iter, COLUMN_FULLNAME);
				func(select, fullname, treestore, iter, data);
				++count;
			}
		}
		return count;
	}

	void sync_with_canvas(CanvasProperties* canvas) {
		import gobject.Value, std.typecons;
		//auto area = main_window.get_draw_area();
		foreach (name ; canvas.itemnames) {
			TreeIter iter = find_iter_for_itemname(name, treestore);
			treestore.setValue(iter, COLUMN_VISUALIZED, scoped!Value(1));
			fix_parent_checkboxes(iter);
		}
	}

	void removeItem(string itemname) {
		TreeIter iter = find_iter_for_itemname(itemname, treestore);
		if (iter !is null) {
			// remove item from plotwidget
			bool activate = false;
			switch_iter(treestore, iter, plotwidget, &activate);
			if (treestore.iterNChildren(iter) > 0) {
				// this iter has children => we cannot remove the row, instead we set fullname to null and color string to ""
				import gobject.Value, std.typecons;
				treestore.setValue(iter, COLUMN_FULLNAME, scoped!Value(""));
				treestore.setValue(iter, COLUMN_IS_ITEM,  scoped!Value(0));
			} else {
				treestore.remove(iter);				
			}
		}
		removeEmptyPaths();
	}
	void removeEmptyPaths() {
		// remove empty paths
		bool dummy = false;
		string[] remove_paths;
		for(;;){
			remove_paths.length = 0;
			iterate_children_depth_first(&dummy, treestore, null, dummy,
				(bool* force_active, string full_name, TreeStore tree_store, TreeIter iter, bool) {

					if (tree_store.iterNChildren(iter) == 0 && tree_store.getInt(iter, COLUMN_IS_ITEM) == 0) {
						remove_paths ~= tree_store.getStringFromIter(iter);
					}
				});
			if (remove_paths.length == 0) {
				break;
			}
			import app, ui;
			foreach(windowname, window; GtkGui.main_windows) {
				window.item_view.removePathNames(remove_paths);
			}
		}
	}
	void removePathNames(string[] pathNames) {
		// pathNames must be in descending order. we reverse the order to make sure that no path is invalidated after removal
		foreach_reverse(remove_path; pathNames) {
			import std.stdio;
			TreeIter iter;
			treestore.getIterFromString(iter, remove_path);
			treestore.remove(iter);
		}
	}	
	
	// TODO: can this be replaced with iterate_children_depth_first?
	TreeIter find_iter_for_itemname(string itemname, TreeStore treestore, TreeIter parent = null) {
		int n_children = treestore.iterNChildren(parent);
		TreeIter iter = null;
		foreach (n ; 0..n_children) {
			if (treestore.iterNthChild(iter, parent, n)) {
				if( treestore.iterNChildren(parent) ) {
					auto found_iter = find_iter_for_itemname(itemname, treestore, iter);
					if (found_iter !is null) {
						return found_iter;
					}
				}
				string fullname = treestore.getString(iter, COLUMN_FULLNAME);
				if (fullname == itemname) {
					return iter;
				}
			}
		}
		return null;
	}

}

// gtk3 compatibility function.
version(gtk3) {
	import gtk.Box;
	void append(ChildWidget)(Box box, ChildWidget child) {
		box.add(child);
	}
} 


import gtk.Box;
class PlotWidget : Box {
	import gtk.CheckButton, gtk.SpinButton, gtk.Button, gtk.Image;
	import gtk.Label, gtk.Separator, gtk.ToggleButton, gtk.ScrolledWindow;

	string name;
	PlotArea plot_area;
	Box      controls;
	ScrolledWindow controls_scrolled_window; // controls are quite wide, so they are contained in a scrolled window

	// all the control elements
	version(gtk3) {
		import gtk.RadioButton;
		alias CheckOrRadioButton = RadioButton;
		alias CheckOrToggleButton = ToggleButton;
	} else {
		alias CheckOrRadioButton = CheckButton;
		alias CheckOrToggleButton = CheckButton;
	}
	CheckButton check_autorefresh;
	Button      button_refresh;
	Label       autoscale_label;
	CheckButton check_autoscale_x, check_autoscale_y, check_autoscale_z;
	Label       log_label;
	CheckButton check_log_x, check_log_y, check_log_z;
	Label       grid_label;
	CheckButton check_grid_x, check_grid_y, check_grid_top;
	Label       nums_label;
	CheckButton check_nums_x, check_nums_y, check_nums_top;
	CheckButton check_colorbar;
	CheckOrRadioButton radio_overlay, radio_rowmajor, radio_colmajor; // grouped to form a gtk3 RadioButton
	SpinButton  spin_n_columns;
	Box         mouse_pos_box;
	Label       mouse_pos;
	Box         mouse_pos_value_box;
	Label       mouse_pos_value;

	version(gtk3) {
		void append(ChildWidget)(ChildWidget ch) {
			add(ch);
		}
	}

	void sync_with_canvas(CanvasProperties *canvas) {
		check_autorefresh.setActive(canvas.autorefresh);
		check_autoscale_x.setActive(canvas.autoscale[0]);
		check_autoscale_y.setActive(canvas.autoscale[1]);
		check_autoscale_z.setActive(canvas.autoscale[2]);
		check_log_x.setActive(canvas.transform[0].logscale);
		check_log_y.setActive(canvas.transform[1].logscale);
		check_log_z.setActive(canvas.transform[2].logscale);
		check_grid_x.setActive(canvas.grid[0]);
		check_grid_y.setActive(canvas.grid[1]);
		check_grid_top.setActive(canvas.grid_ontop);
		check_nums_x.setActive(canvas.numbers[0]);
		check_nums_y.setActive(canvas.numbers[1]);
		check_nums_top.setActive(canvas.numbers_ontop);
		check_colorbar.setActive(canvas.color_bar);
		spin_n_columns.setValue(canvas.columns_or_rows);
		if (canvas.display_mode == DisplayMode.overlay) radio_overlay.setActive(true);
		if (canvas.display_mode == DisplayMode.rows)    radio_rowmajor.setActive(true);
		if (canvas.display_mode == DisplayMode.columns) radio_colmajor.setActive(true);
	}

	this(CanvasProperties *canvas, string window_name) {
		import ui;

		super(GtkOrientation.VERTICAL, 0); // PlotWidget derived from Box
		name = window_name;
		///////////////////////////////////////////////
		// place two top-level widgets
		///////////////////////////////////////////////
		plot_area = new PlotArea(canvas, &setMousePosLabel, &setMousePosLabelValue);
		plot_area.setVexpand(true);
		controls = new Box(GtkOrientation.HORIZONTAL, 0);
		controls_scrolled_window = new ScrolledWindow();
		controls_scrolled_window.setPropagateNaturalWidth(true);
		controls_scrolled_window.setPropagateNaturalHeight(true);
		controls_scrolled_window.setChild(controls);

		append(plot_area);
		append(new Separator(GtkOrientation.HORIZONTAL));
		append(controls_scrolled_window);

		///////////////////////////////////////////////
		// instanciate all the controls
		///////////////////////////////////////////////
		check_autorefresh = new CheckButton("auto\nrefr.");
		check_autorefresh.setActive(canvas.autorefresh);
		check_autorefresh.addOnToggled(
				delegate void(CheckOrToggleButton button) {
					ui.winpoll(name, button.getActive()?"true":"false");
				}
			);

		button_refresh = new Button("refr.");
		button_refresh.addOnClicked((button) => ui.winrefresh(name));

		///////////////////////////////////////////////////////
		autoscale_label = new Label("fit");
		check_autoscale_x = new CheckButton("X");
		check_autoscale_y = new CheckButton("Y");
		check_autoscale_z = new CheckButton("Z");
		check_autoscale_x.setActive(canvas.autoscale[0]);
		check_autoscale_y.setActive(canvas.autoscale[1]);
		check_autoscale_z.setActive(canvas.autoscale[2]);
		check_autoscale_x.addOnToggled((button) => autoscale(name, 'x', button.getActive()?"true":"false"));
		check_autoscale_y.addOnToggled((button) => autoscale(name, 'y', button.getActive()?"true":"false"));
		check_autoscale_z.addOnToggled((button) => autoscale(name, 'z', button.getActive()?"true":"false"));

		///////////////////////////////////////////////////////
		log_label = new Label("log");
		check_log_x = new CheckButton("X");
		check_log_y = new CheckButton("Y");
		check_log_z = new CheckButton("Z");
		check_log_x.setActive(canvas.transform[0].logscale);
		check_log_y.setActive(canvas.transform[1].logscale);
		check_log_z.setActive(canvas.transform[2].logscale);
		check_log_x.addOnToggled((button) => logscale(name, 'x', button.getActive()?"true":"false"));
		check_log_y.addOnToggled((button) => logscale(name, 'y', button.getActive()?"true":"false"));
		check_log_z.addOnToggled((button) => logscale(name, 'z', button.getActive()?"true":"false"));

		///////////////////////////////////////////////////////
		grid_label     = new Label("grid");
		check_grid_x   = new CheckButton("X");
		check_grid_y   = new CheckButton("Y");
		check_grid_top = new CheckButton("top");
		check_grid_x.setActive(canvas.grid[0]);
		check_grid_y.setActive(canvas.grid[1]);
		check_grid_top.setActive(canvas.grid_ontop);
		check_grid_x.addOnToggled((button)   => grid(name,  "x",  button.getActive()?"true":"false"));
		check_grid_y.addOnToggled((button)   => grid(name,  "y",  button.getActive()?"true":"false"));
		check_grid_top.addOnToggled((button) => grid(name, "top", button.getActive()?"true":"false"));

		nums_label     = new Label("nums");
		check_nums_x   = new CheckButton("X");
		check_nums_y   = new CheckButton("Y");
		check_nums_top = new CheckButton("top");
		check_nums_x.setActive(canvas.numbers[0]);
		check_nums_y.setActive(canvas.numbers[1]);
		check_nums_top.setActive(canvas.numbers_ontop);
		check_nums_x.addOnToggled(  (button) => ui.numbers(name,  "x" , button.getActive()?"true":"false"));
		check_nums_y.addOnToggled(  (button) => ui.numbers(name,  "y" , button.getActive()?"true":"false"));
		check_nums_top.addOnToggled((button) => ui.numbers(name, "top", button.getActive()?"true":"false"));


		check_colorbar = new CheckButton("colorbar");
		check_colorbar.setActive(canvas.color_bar);
		check_colorbar.addOnToggled( (button) => ui.colorbar(name, button.getActive()?"true":"false"));


		radio_overlay  = new CheckOrRadioButton("overlay");
		radio_rowmajor = new CheckOrRadioButton("rows");
		radio_colmajor = new CheckOrRadioButton("columns");
		version(gtk3){ 
			radio_colmajor.joinGroup(radio_overlay);
			radio_rowmajor.joinGroup(radio_overlay);
		} else {
			radio_colmajor.setGroup(radio_overlay);
			radio_rowmajor.setGroup(radio_overlay);
		}
		if (canvas.display_mode == DisplayMode.overlay) radio_overlay.setActive(true);
		if (canvas.display_mode == DisplayMode.rows)    radio_rowmajor.setActive(true);
		if (canvas.display_mode == DisplayMode.columns) radio_colmajor.setActive(true);
		radio_overlay.addOnToggled(delegate void(CheckOrToggleButton button) {	if (button.getActive()) ui.overlay(name); });
		radio_rowmajor.addOnToggled(delegate void(CheckOrToggleButton button) {	if (button.getActive()) ui.rows   (name, cast(int)spin_n_columns.getValue); });
		radio_colmajor.addOnToggled(delegate void(CheckOrToggleButton button) {	if (button.getActive()) ui.columns(name, cast(int)spin_n_columns.getValue); });

		spin_n_columns = new SpinButton(1,50,1);
		spin_n_columns.setValue(canvas.columns_or_rows);
		spin_n_columns.addOnValueChanged(
			delegate void(SpinButton button) {
				if (canvas.display_mode == DisplayMode.rows)    ui.rows   (name, cast(int)button.getValue);
				if (canvas.display_mode == DisplayMode.columns) ui.columns(name, cast(int)button.getValue);
			} );

//		///////////////////////////////////////////////////////

		mouse_pos = new Label("  x=0\n  y=0");
		mouse_pos.setJustify(GtkJustification.LEFT);
		mouse_pos_box = new Box(GtkOrientation.HORIZONTAL, 0);
		mouse_pos_box.setSizeRequest(150,0);
		mouse_pos_box.append(mouse_pos);
		mouse_pos_value = new Label("\nvalue=nan");
		mouse_pos_value.setJustify(GtkJustification.LEFT);
		mouse_pos_value_box = new Box(GtkOrientation.HORIZONTAL, 0);
		mouse_pos_value_box.setSizeRequest(150,0);
		mouse_pos_value_box.append(mouse_pos_value);



		///////////////////////////////////////////////
		// add all controls into the Box Widget
		///////////////////////////////////////////////
		controls.append(check_autorefresh);
		controls.append(button_refresh);

		//controls.append(new Separator(GtkOrientation.VERTICAL));
		auto fit_log_labels = new Box(GtkOrientation.VERTICAL, 0);
		fit_log_labels.append(autoscale_label);
		fit_log_labels.append(log_label);

		auto fit_log_checks_x = new Box(GtkOrientation.VERTICAL, 0);
		fit_log_checks_x.append(check_autoscale_x);
		fit_log_checks_x.append(check_log_x);

		auto fit_log_checks_y = new Box(GtkOrientation.VERTICAL, 0);
		fit_log_checks_y.append(check_autoscale_y);
		fit_log_checks_y.append(check_log_y);

		auto fit_log_checks_z = new Box(GtkOrientation.VERTICAL, 0);
		fit_log_checks_z.append(check_autoscale_z);
		fit_log_checks_z.append(check_log_z);

		controls.append(fit_log_labels);
		controls.append(fit_log_checks_x);
		controls.append(fit_log_checks_y);
		controls.append(fit_log_checks_z);

		controls.append(new Separator(GtkOrientation.VERTICAL));

		auto grid_nums_label = new Box(GtkOrientation.VERTICAL, 0);
		grid_nums_label.append(grid_label);
		grid_nums_label.append(nums_label);

		auto grid_nums_checks_x = new Box(GtkOrientation.VERTICAL, 0);
		grid_nums_checks_x.append(check_grid_x);
		grid_nums_checks_x.append(check_nums_x);

		auto grid_nums_checks_y = new Box(GtkOrientation.VERTICAL, 0);
		grid_nums_checks_y.append(check_grid_y);
		grid_nums_checks_y.append(check_nums_y);

		auto grid_nums_checks_top = new Box(GtkOrientation.VERTICAL, 0);
		grid_nums_checks_top.append(check_grid_top);
		grid_nums_checks_top.append(check_nums_top);

		controls.append(grid_nums_label);
		controls.append(grid_nums_checks_x);
		controls.append(grid_nums_checks_y);
		controls.append(grid_nums_checks_top);

		auto colorbar_overlay = new Box(GtkOrientation.VERTICAL, 0);
		colorbar_overlay.append(check_colorbar);
		colorbar_overlay.append(radio_overlay);
		controls.append(colorbar_overlay);
		controls.append(new Separator(GtkOrientation.VERTICAL));
		controls.append(spin_n_columns);
		auto row_col_radios = new Box(GtkOrientation.VERTICAL, 0);
		row_col_radios.append(radio_rowmajor);
		row_col_radios.append(radio_colmajor);
		controls.append(row_col_radios);

		controls.append(new Separator(GtkOrientation.VERTICAL));
		controls.append(mouse_pos_box);
		controls.append(mouse_pos_value_box);

	}

	void setMousePosLabel(double x, double y) {
		import std.format;
		auto label = format("  x=%g\n  y=%g", x,y);
		mouse_pos.setLabel(label);
		mouse_pos.setJustify(GtkJustification.LEFT);
	}
	void setMousePosLabelValue(double value, string name) {
		import std.format;
		if (name !is null && name != "") {
			auto label = format(" %s\n value=%g", name, value);
			mouse_pos_value.setLabel(label);
		} else {
			mouse_pos_value.setLabel("");
		}
	}	
}

//import draw;
import gtk.DrawingArea;
class PlotArea :  DrawingArea, BackendInterface {

	import gtk.c.types;
	import gtk.c.functions;
	import cairo.c.types;
	import cairo.c.functions;
	cairo_t* cr;
	int width, height;
	void set_cr(cairo_t* c, int w, int h) {
		cr = c;
		width = w;
		height = h;
	}

	override bool inverted_y_direction() {
		return true;
	}
	override bool text_with_border() {
		return true;
	}

	override void initialize() {
	}

	override void finish() {
	}

	override void reset_clip() {
		cairo_reset_clip(cr);
		cairo_rectangle(cr, 0,0, width, height);		
		cairo_clip(cr);
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		cairo_reset_clip(cr);
		cairo_rectangle(cr, x1,y1, x2-x1, y2-y1);		
		cairo_clip(cr);
	}
	override void clear(double r, double g, double b) {
		cairo_save(cr);
		cairo_set_source_rgba(cr, r,g,b,1);
		cairo_paint(cr);
		cairo_restore(cr);		
	}
	override void set_color(double r, double g, double b) {
		cairo_set_source_rgba(cr, r,g,b,1);
	}
	double line_width;
	override void set_line_width(double w) {
		line_width = w;
		cairo_set_line_width(cr, w);
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double x, double y1, double y2) {
		cairo_move_to(cr, x, y1);
		cairo_line_to(cr, x, y2);
	}
	override void horizontal_line(double y, double x1, double x2) {
		cairo_move_to(cr, x1, y);
		cairo_line_to(cr, x2, y);
	}
	override void line(double x1, double y1, double x2, double y2) {
		cairo_move_to(cr, x1, y1);
		cairo_line_to(cr, x2, y2);
	}
	void rectangle(double x1, double y1, double x2, double y2)
	{
		cairo_rectangle(cr, x1,y1, x2-x1, y2-y1);
	}
	override void fill() {
		cairo_fill(cr);
	}
	override void stroke() {
		cairo_stroke(cr);
	}

	import cairo.ImageSurface, cairo.Pattern;
	struct Bitmap {
		uint[] data;
		ImageSurface surface;
		Pattern pattern;
		int w,h;
		int stride;
	}
	Bitmap[ulong] bitmaps;
	ulong bitmap_counter = 0;
	@trusted
	override ulong    create_bitmap(int w, int h) {
		import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		ulong handle = ++bitmap_counter;

		Bitmap bmp;
		auto stride = ImageSurface.formatStrideForWidth(CairoFormat.ARGB32, w);
		bmp.data = new uint[](w*h);
		bmp.w = w;
		bmp.h = h;
		bmp.stride = stride;		

		bmp.surface = ImageSurface.createForData(cast(ubyte*)bmp.data.ptr, CairoFormat.ARGB32, w, h, stride);
		bmp.pattern = Pattern.createForSurface(bmp.surface);
		bmp.pattern.setFilter(CairoFilter.NEAREST);

		bitmaps[handle] = bmp;
		return handle;
	}
	override void   destroy_bitmap(ulong handle) {
		import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		bitmaps[handle].data = null;
		bitmaps[handle].pattern.destroy;
		bitmaps[handle].surface.destroy;
		bitmaps.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		return bitmaps[handle].data;
	}
	override void    access_bitmap_done(ulong handle) {
		import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		bitmaps[handle].surface.destroy;
		bitmaps[handle].pattern.destroy;
		bitmaps[handle].surface = ImageSurface.createForData(cast(ubyte*)bitmaps[handle].data.ptr, CairoFormat.ARGB32, bitmaps[handle].w, bitmaps[handle].h, bitmaps[handle].stride);
		bitmaps[handle].pattern = Pattern.createForSurface(bitmaps[handle].surface);
		bitmaps[handle].pattern.setFilter(CairoFilter.NEAREST);
	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                                  double dx, double dy, double dw, double dh) {
		import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		cairo_save(cr);
			cairo_translate(cr, dx,dy);
			cairo_scale(cr, dw/sw, dh/sh);
			cairo_translate(cr,-sx,-sy);
			cairo_rectangle(cr, sx,sy, sw,sh);
			cairo_set_source(cr, bitmaps[handle].pattern.getPatternStruct());
			cairo_fill(cr);
		cairo_restore(cr);
	}

	override void need_redraw() {
		queueDraw();
	}

	override void show_mouse_pos(double x, double y, double z) {
		updateMousePosLabel(x,y);
	}
	override void show_value(double value, string itemname) {
		updateValue(value, itemname);
	}
	override void set_text_size(int s) {
		cairo_set_font_size(cr, s);
	}

	override void text_extent(string str, out double w, out double h) {
		//cairo_text_extents (cairo_t *cr, const char *utf8, cairo_text_extents_t *extents);.
		cairo_text_extents_t cte;
		import std.string, std.typecons;
		auto strz = cast(char*)str.dup.toStringz;
		cairo_text_extents(cr, strz, &cte);
		w=cte.width;
		h=cte.height;
	}
	override void text(double x, double y, string str) {
		import std.string, std.typecons;
		auto strz = cast(char*)str.dup.toStringz;
		cairo_text_extents_t cte;
		cairo_text_extents(cr, strz, &cte);
		cairo_move_to(cr, x, y); 
		cairo_show_text(cr, strz);
	}

	version(gtk4) {
		import gtk.EventControllerMotion;
		import gtk.EventControllerScroll, gtk.c.types;
		import gtk.GestureClick, gdk.c.types;
		EventControllerMotion motion_controller;
		EventControllerScroll scroll_controller;
		GestureClick left_click;
		GestureClick right_click;
		GestureClick middle_click;
	}

	this(CanvasProperties *canvas, 
		 void delegate(double,double) @trusted updateMousePosLabel_func ,
		 void delegate(double,string) @trusted updateValue_func) 
	{
//		draw_area.drawer = this;
		painter = CanvasPainter(canvas, this);

		updateMousePosLabel = updateMousePosLabel_func;
		updateValue         = updateValue_func;

//		// minimum size of PlotArea
		setSizeRequest(100, 50);
 
		version(gtk3) {
			addOnDraw(&drawCallback);
			addOnMotionNotify(delegate bool(GdkEventMotion *event_motion, Widget w){
				double x = event_motion.x, y = event_motion.y;
				bool ctrl  = (event_motion.state & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (event_motion.state & GdkModifierType.SHIFT_MASK  ) != 0;
				painter.mouse_motion(x,y, cast(PlotArea)w, ctrl, shift);
				return false;
			});
		    addOnButtonPress(delegate bool(GdkEventButton *event_button, Widget w) {
				import gdk.Event;
				int nPress = Event.isDoubleClick(event_button)?2:1;
				PlotArea plot_area = cast(PlotArea)w;
				double x = event_button.x, y = event_button.y;
				bool ctrl  = (event_button.state & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (event_button.state & GdkModifierType.SHIFT_MASK  ) != 0;
				if (event_button.button == 1) painter.left_button_pressed (nPress,x,y,ctrl,shift);
				if (event_button.button == 2) painter.mid_button_pressed  (nPress,x,y,this,ctrl,shift);		
				if (event_button.button == 3) painter.right_button_pressed(nPress,x,y,ctrl,shift);
				return false;
			});
		    addOnButtonRelease(delegate bool(GdkEventButton *event_button, Widget w) {
				import gdk.Event;
				int nPress = Event.isDoubleClick(event_button)?2:1;
				PlotArea plot_area = cast(PlotArea)w;
				double x = event_button.x, y = event_button.y;
				bool ctrl  = (event_button.state & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (event_button.state & GdkModifierType.SHIFT_MASK  ) != 0;
				if (event_button.button == 1) painter.left_button_released (nPress,x,y,ctrl,shift);
				if (event_button.button == 2) painter.mid_button_released  (nPress,x,y,ctrl,shift);		
				if (event_button.button == 3) painter.right_button_released(nPress,x,y,ctrl,shift);
				return false;
			});
			addOnScroll(delegate bool(GdkEventScroll *event_scroll, Widget w) {
				import gdk.Event;
				//double x = event_scroll.x, y = event_scroll.y;
				PlotArea plot_area = cast(PlotArea)w;
				bool ctrl  = (event_scroll.state & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (event_scroll.state & GdkModifierType.SHIFT_MASK  ) != 0;
				final switch(event_scroll.direction)
				{
					case GdkScrollDirection.DOWN:  painter.scroll( 0 , 1, ctrl, shift);  break;
					case GdkScrollDirection.UP:	   painter.scroll( 0 ,-1, ctrl, shift);  break;
					case GdkScrollDirection.LEFT:  painter.scroll(-1 , 0, ctrl, shift);  break;
					case GdkScrollDirection.RIGHT: painter.scroll( 1 , 0, ctrl, shift);  break;
					case GdkScrollDirection.SMOOTH:						 break;
				}
				return true;								
			});


		} 

		version(gtk4) { 
			///////////////////////////////////////////
			// mouse motion
			///////////////////////////////////////////
			setDrawFunc(&drawFunc, cast(void*)this, &destroyNotify);
			// detect mouse motion in the PlotArea
			import gtk.EventControllerMotion;
			motion_controller = new EventControllerMotion();
			//gulong addOnMotion(void delegate(double, double, EventControllerMotion) dlg, ConnectFlags connectFlags=cast(ConnectFlags)0)
			motion_controller.addOnMotion(delegate(double x, double y, EventControllerMotion controller) {
				bool ctrl  = (controller.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (controller.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				mouse_motion(x,y, cast(PlotArea)controller.getWidget(), ctrl, shift);
			});

			addController(motion_controller); 

			///////////////////////////////////////////
			// mouse wheel 
			///////////////////////////////////////////
			import gtk.EventControllerScroll, gtk.c.types;
			scroll_controller = new EventControllerScroll(GtkEventControllerScrollFlags.VERTICAL | 
			                                                   GtkEventControllerScrollFlags.HORIZONTAL);
			scroll_controller.addOnScroll(delegate bool(double dx, double dy, EventControllerScroll controller) {
				bool ctrl  = (controller.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (controller.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				scroll(dx,dy, ctrl, shift);
				return true;
			});
			addController(scroll_controller);


			///////////////////////////////////////////
			// detect mouse clicks in the PlotArea
			///////////////////////////////////////////
			import gtk.GestureClick, gdk.c.types;
			left_click = new GestureClick;
			addController(left_click);
			left_click.setButton(BUTTON_PRIMARY); 
			left_click.addOnPressed(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				left_button_pressed(nPress,x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});
			left_click.addOnReleased(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				left_button_released(nPress,x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});

			right_click = new GestureClick;
			addController(right_click);
			right_click.setButton(BUTTON_SECONDARY); 
			right_click.addOnPressed(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				right_button_pressed(nPress,x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});
			right_click.addOnReleased(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				right_button_released(nPress, x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});

			middle_click = new GestureClick;
			addController(middle_click);
			middle_click.setButton(BUTTON_MIDDLE); 
			middle_click.addOnPressed(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				mid_button_pressed(nPress,x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});
			middle_click.addOnReleased(delegate void(int nPress, double x, double y, GestureClick g) {
				bool ctrl  = (g.getCurrentEventState() & GdkModifierType.CONTROL_MASK) != 0;
				bool shift = (g.getCurrentEventState() & GdkModifierType.SHIFT_MASK)   != 0;
				mid_button_released(nPress, x,y, cast(PlotArea)g.getWidget(), ctrl, shift);
			});
		}



	}

private:

	CanvasPainter painter;

	version(gtk3) {
		import cairo.Context, cairo.Surface;
		bool drawCallback(Scoped!Context cr, Widget widget) {
			GtkAllocation size;
			getAllocation(size);		
			drawFunc(null, cr.getContextStruct, size.width, size.height, cast(void*)this);
			return true;
		}
	}
	extern(C) 
	static void drawFunc(GtkDrawingArea* drawingArea, cairo_t* cr, int width, int height, void* userData) {
		GtkAllocation size;
		auto plot_area = cast(PlotArea)userData;
		plot_area.getAllocation(size);
		//plot_area.painter.resize(size.width,size.height);
		plot_area.painter.canvas.width = size.width;
		plot_area.painter.canvas.height = size.height;
		plot_area.cr = cr;
		plot_area.painter.draw_content();
	}
	extern(C) 
	static void destroyNotify(void *data) {
	}

	/////////////////////////////////////////////////////////
	// handle mouse motion and mouse  button press and release
	/////////////////////////////////////////////////////////
	void mouse_motion(double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.mouse_motion(x,y,this,ctrl,shift);
	}
	void right_button_pressed(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		GtkAllocation size;	getAllocation(size);
		//painter.resize(size.width,size.height);
		painter.canvas.width = size.width;
		painter.canvas.height = size.height;
		painter.right_button_pressed(nPress,x,y,ctrl,shift);
	}
	void right_button_released(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.right_button_released(nPress,x,y,ctrl,shift);
	}
	void mid_button_pressed(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.mid_button_pressed(nPress,x,y,this,ctrl,shift);
	}
	void mid_button_released(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.mid_button_released(nPress,x,y,ctrl,shift);
	}
	void left_button_pressed(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.left_button_pressed(nPress,x,y,ctrl,shift);
	}
	void left_button_released(int nPress, double x, double y, PlotArea pa, bool ctrl = false, bool shift = false) {
		painter.left_button_released(nPress,x,y,ctrl,shift);
	}
	/////////////////////////////////////////////////////////
	// scrolling functions (mouse wheel)
	/////////////////////////////////////////////////////////
	void scroll(double dx, double dy, bool ctrl = false, bool shift = false) {
		import std.stdio;
		GtkAllocation size;
		getAllocation(size);
		//painter.resize(size.width,size.height);
		painter.canvas.width = size.width;
		painter.canvas.height = size.height;
		painter.scroll(dx, dy, ctrl, shift);
	}

	void delegate(double, double) updateMousePosLabel;
	void delegate(double, string) updateValue;


}



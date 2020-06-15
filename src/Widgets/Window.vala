/*
* Copyright (c) 2020 Louis Brauer (https://github.com/louis77)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Louis Brauer <louis@brauer.family>
*/

using Gee;

public class Tuner.Window : Gtk.ApplicationWindow {
    public GLib.Settings settings;
    public Gtk.Stack stack { get; set; }

    private PlayerController _player;
    private DirectoryController _directory;
    private HeaderBar headerbar;
    private delegate void ActionFunc (ContentBox target);

    public const string ACTION_PREFIX = "win.";
    public const string ACTION_PAUSE = "action_pause";
    public const string ACTION_QUIT = "action_quit";

    private const ActionEntry[] ACTION_ENTRIES = {
        { ACTION_PAUSE, handle_stop_playback },
        { ACTION_QUIT, action_quit }
    };

    public Window (Application app, PlayerController player) {
        Object (application: app);

        application.set_accels_for_action (ACTION_PREFIX + ACTION_PAUSE, {"<Control>5"});
        application.set_accels_for_action (ACTION_PREFIX + ACTION_QUIT, {"<Control>q", "<Control>w"});

        _player = player;
        _player.state_changed.connect (handle_player_state_changed);
        _player.station_changed.connect (headerbar.update_from_station);
    }

    static construct {
        var provider = new Gtk.CssProvider ();
        provider.load_from_resource ("com/github/louis77/tuner/Application.css");
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider,                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    construct {
        add_action_entries (ACTION_ENTRIES, this);

        window_position = Gtk.WindowPosition.CENTER;
        set_default_size (350, 80);
        settings = Application.instance.settings;
        move (settings.get_int ("pos-x"), settings.get_int ("pos-y"));
        resize (default_width, default_height);

        delete_event.connect (e => {
            return before_destroy ();
        });

        headerbar = new HeaderBar (this);
        headerbar.stop_clicked.connect ( () => {
            handle_stop_playback ();
        });
        headerbar.star_clicked.connect ( (starred) => {
            _directory.star_station (_player.station, starred);
        });
        set_titlebar (headerbar);

        _directory = new DirectoryController (new RadioBrowser.Client ());
        _directory.stations_updated.connect (handle_updated_stations);

        var primary_box = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
        var stack = new Gtk.Stack ();
        stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

        var selections_category = new Granite.Widgets.SourceList.ExpandableItem ("Selections");
        selections_category.collapsible = false;
        selections_category.expanded = true;

        create_content_box ("discover", "Discover", "face-smile",
                            "Discover Stations", "media-playlist-shuffle-symbolic",
                            "Discover more stations",
                            _directory.load_random_stations, stack, selections_category);

        create_content_box ("trending", "Trending", "playlist-queue",
                            "Trending Stations", "go-next",
                            "Load more stations",
                            _directory.load_trending_stations, stack, selections_category);

        create_content_box ("popular", "Popular", "playlist-similar",
                            "Popular Stations", "go-next",
                            "Load more stations",
                            _directory.load_popular_stations, stack, selections_category);

        create_content_box ("starred", "Starred by You", "starred",
                            "Starred by You", "view-refresh-symbolic",
                            "Refresh",
                            _directory.load_favourite_stations, stack, selections_category);

        var source_list = new Granite.Widgets.SourceList ();
        source_list.root.add (selections_category);
        source_list.set_size_request (150, -1);
        source_list.selected = source_list.get_first_child (selections_category);
        source_list.item_selected.connect  ((item) => {
            var selected_item = item.get_data<string> ("stack_child");
            debug (@"selected $selected_item");
            stack.visible_child_name = selected_item;

        });

        primary_box.pack1 (source_list, true, false);
        primary_box.pack2 (stack, true, false);
        add (primary_box);
        show_all ();
    }

    private void create_content_box (string name,
                                     string list_title,
                                     string list_icon_name,
                                     string full_title,
                                     string action_icon_name,
                                     string action_tooltip_text,
                                     ActionFunc action_func,
                                     Gtk.Stack stack,
                                     Granite.Widgets.SourceList.ExpandableItem category_item) {
        var c = new ContentBox (
            null,
            full_title,
            action_icon_name,
            action_tooltip_text
        );
        c.selection_changed.connect (handle_station_click);
        c.map.connect (() => {
            if (!c.get_data<bool> ("has_stations")) {
                action_func (c);
                c.set_data<bool> ("has_stations", true);
            }
        });
        c.action_activated.connect (() => {
            action_func (c);
        });

        stack.add_named (c, name);

        var item = new Granite.Widgets.SourceList.Item (list_title);
        item.icon = new ThemedIcon (list_icon_name);
        item.set_data<string> ("stack_child", name);
        category_item.add (item);
    }

    private void action_quit () {
        destroy ();
    }

    public void handle_updated_stations (ContentBox target, ArrayList<Model.StationModel> stations) {
        debug ("entering handle_updated_stations");
        target.stations = stations;

        // set_geometry_hints (null, null, Gdk.WindowHints.MIN_SIZE);
        show_all ();
        // resize (default_width, default_height);
        // var scrolled_window = new Gtk.ScrolledWindow (null, null);
        // scrolled_window.add (content);
        // add (scrolled_window);
    }

    public void handle_station_click(Tuner.Model.StationModel station) {
        info (@"handle station click for $(station.title)");
        _directory.count_station_click (station);
        _player.station = station;
    }

    public void handle_stop_playback() {
        info ("Stop Playback requested");
        _player.play_pause ();
    }

    public void handle_player_state_changed (Gst.PlayerState state) {
        switch (state) {
            case Gst.PlayerState.BUFFERING:
                debug ("player state changed to Buffering");
                Gdk.threads_add_idle (() => {
                    headerbar.subtitle = "Buffering";
                    headerbar.set_playstate (headerbar.PAUSE_ACTIVE);
                    return false;
                });
                break;;
            case Gst.PlayerState.PAUSED:
                debug ("player state changed to Paused");
                Gdk.threads_add_idle (() => {
                    headerbar.subtitle = "Paused";
                    if (_player.can_play()) {
                        headerbar.set_playstate (headerbar.PLAY_ACTIVE);
                    } else {
                        headerbar.set_playstate (headerbar.PLAY_INACTIVE);
                    }
                    return false;
                });
                break;;
            case Gst.PlayerState.PLAYING:
                debug ("player state changed to Playing");
                Gdk.threads_add_idle (() => {
                    headerbar.subtitle = _("Playing");
                    headerbar.set_playstate (headerbar.PAUSE_ACTIVE);
                    return false;
                });
                break;;
            case Gst.PlayerState.STOPPED:
                debug ("player state changed to Stopped");
                Gdk.threads_add_idle (() => {
                    headerbar.subtitle = _("Stopped");
                    if (_player.can_play()) {
                        headerbar.set_playstate (headerbar.PLAY_ACTIVE);
                    } else {
                        headerbar.set_playstate (headerbar.PLAY_INACTIVE);
                    }
                    return false;
                });
                break;
        }

        return;
    }

    public bool before_destroy () {
        int width, height, x, y;

        get_size (out width, out height);
        get_position (out x, out y);

        settings.set_int ("pos-x", x);
        settings.set_int ("pos-y", y);
        settings.set_int ("window-height", height);
        settings.set_int ("window-width", width);

        return false;
    }

}

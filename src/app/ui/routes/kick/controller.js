import Controller from "@ember/controller";
import { inject as service } from "@ember/service";
import { set } from "@ember/object";

export default Controller.extend({
	settings: service(),
	loading: true,
	error: null,
	streams: null,

	init() {
		this._super( ...arguments );
		set( this, "streams", [] );
	},

	actions: {
		play( slug ) {
			if ( !slug ) { return; }
			const streaming = this.settings.content.streaming;
			const provider = streaming.provider;
			const config = streaming.providers[ provider ];
			const executable = config && ( config.exec || config.executable );
			if ( !executable ) {
				set( this, "error", "Set a Streamlink executable in Settings → Streaming before playing Kick streams." );
				return;
			}
			const spawn = require( "child_process" ).spawn;
			const args = [ "https://kick.com/" + slug, "best" ];
			const child = spawn( executable, args, { detached: true, stdio: "ignore" } );
			child.once( "error", error => set( this, "error", error.message ) );
			child.unref();
		},

		openBrowser( slug ) {
			if ( !slug ) { return; }
			require( "nw.gui" ).Shell.openExternal( "https://kick.com/" + slug );
		}
	}
});

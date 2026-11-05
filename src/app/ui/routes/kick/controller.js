import Controller from "@ember/controller";
import { set } from "@ember/object";

const { spawn } = require( "child_process" );

export default Controller.extend({
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
			set( this, "error", null );

			const args = [ `https://kick.com/${slug}`, "best" ];
			const child = spawn( "streamlink", args, { windowsHide: true } );
			let output = "";
			let failed = false;

			const appendOutput = chunk => {
				output = ( output + chunk.toString() ).slice( -3000 );
			};
			child.stdout.on( "data", appendOutput );
			child.stderr.on( "data", appendOutput );

			child.once( "error", error => {
				failed = true;
				set( this, "error", `Could not start Streamlink: ${error.message}` );
			});
			child.once( "exit", code => {
				if ( code !== 0 && !failed ) {
					const message = output.trim() || `Streamlink exited with code ${code}`;
					set( this, "error", message );
				}
			});
		},

		openBrowser( slug ) {
			if ( !slug ) { return; }
			require( "nw.gui" ).Shell.openExternal( `https://kick.com/${slug}` );
		}
	}
});

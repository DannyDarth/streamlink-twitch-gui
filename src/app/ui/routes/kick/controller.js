import Controller from "@ember/controller";
import { inject as service } from "@ember/service";
import { set } from "@ember/object";
import resolveProvider from "services/streaming/provider/resolve";
import resolvePlayer from "services/streaming/player/resolve";
import spawn from "services/streaming/spawn";

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
		async play( slug ) {
			if ( !slug ) { return; }
			set( this, "error", null );

			try {
				const settings = this.settings.content.streaming.toJSON();
				const stream = { isAborted: false };
				const provider = await resolveProvider(
					stream,
					settings.provider,
					settings.providers
				);
				const player = await resolvePlayer(
					stream,
					settings.player,
					settings.players
				);
				const args = [];
				if ( player.exec ) {
					args.push( "--player", player.exec );
				}
				if ( player.params ) {
					args.push( "--player-args", player.params );
				}
				args.push( `https://kick.com/${slug}`, settings.quality || "best" );
				const child = spawn( provider, args, {
					detached: true,
					stdio: "ignore"
				});
				child.once( "error", error => {
					set( this, "error", error.message );
				});
				child.unref();
			} catch ( error ) {
				set( this, "error", error.message );
			}
		},

		openBrowser( slug ) {
			if ( !slug ) { return; }
			require( "nw.gui" ).Shell.openExternal( `https://kick.com/${slug}` );
		}
	}
});

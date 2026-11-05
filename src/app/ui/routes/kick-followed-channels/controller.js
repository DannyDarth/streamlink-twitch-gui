import Controller from "@ember/controller";
import { set } from "@ember/object";
import { getFavorites, saveFavorites } from "ui/utils/kick-favorites";

const { spawn } = require( "child_process" );

export default Controller.extend({
	favorites: null,
	channels: null,
	channelInput: "",
	loading: false,
	error: null,
	refreshGeneration: 0,

	init() {
		this._super( ...arguments );
		set( this, "favorites", getFavorites() );
		set( this, "channels", [] );
		this.refreshChannels();
	},

	async refreshChannels() {
		const generation = this.refreshGeneration + 1;
		set( this, "refreshGeneration", generation );
		const slugs = getFavorites();
		set( this, "favorites", slugs );
		set( this, "loading", true );
		set( this, "error", null );
		set( this, "channels", slugs.map( slug => ({ slug, checking: true }) ) );
		for ( let i = 0; i < slugs.length; i += 5 ) {
			await Promise.all( slugs.slice( i, i + 5 ).map( async slug => {
				const item = this.channels.find( row => row.slug === slug );
				try {
					const response = await fetch(
						`https://kick.com/api/v2/channels/${encodeURIComponent( slug )}/livestream`,
						{ credentials: "omit" }
					);
					if ( !response.ok ) {
						throw new Error( `HTTP ${response.status}` );
					}
					const result = await response.json();
					const live = result.data || result;
					if ( generation !== this.refreshGeneration ) { return; }
					const isLive = Boolean( live && live.id );
					set( item, "isLive", isLive );
					if ( isLive ) {
						const count = live.viewers ?? live.viewcount ?? live.viewer_count;
						set( item, "viewers", count == null
							? "—" : Number( count ).toLocaleString() );
						set( item, "title", live.session_title || live.title || "" );
					}
				} catch ( error ) {
					if ( generation !== this.refreshGeneration ) { return; }
					set( item, "error", error.message );
				} finally {
					if ( generation === this.refreshGeneration ) {
						set( item, "checking", false );
					}
				}
			}));
		}
		if ( generation === this.refreshGeneration ) {
			set( this, "loading", false );
		}
	},

	actions: {
		addFavorite() {
			const value = ( this.channelInput || "" )
				.trim()
				.replace( /^https?:\/\/(?:www\.)?kick\.com\//i, "" )
				.replace( /^\/+|\/+$/g, "" );
			if ( !/^[a-zA-Z0-9_-]+$/.test( value ) ) {
				set( this, "error", "Enter a valid Kick channel name." );
				return;
			}
			saveFavorites( [ ...getFavorites(), value ] );
			set( this, "channelInput", "" );
			this.refreshChannels();
		},
		removeFavorite( slug ) {
			saveFavorites( getFavorites().filter( value => value !== slug ) );
			this.refreshChannels();
		},
		refresh() {
			this.refreshChannels();
		},
		play( slug ) {
			if ( !slug ) { return; }
			set( this, "error", null );
			const child = spawn( "streamlink",
				[ `https://kick.com/${slug}`, "best" ], { windowsHide: true } );
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
					set( this, "error", output.trim()
						|| `Streamlink exited with code ${code}` );
				}
			});
		},
		openBrowser( slug ) {
			require( "nw.gui" ).Shell.openExternal( `https://kick.com/${slug}` );
		}
	}
});

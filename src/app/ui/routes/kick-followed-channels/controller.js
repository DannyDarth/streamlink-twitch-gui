import Controller from "@ember/controller";
import { set } from "@ember/object";
import { getFavorites, saveFavorites } from "ui/utils/kick-favorites";

export default Controller.extend({
	favorites: null,
	channelInput: "",

	init() {
		this._super( ...arguments );
		set( this, "favorites", getFavorites() );
	},

	actions: {
		addFavorite() {
			const value = ( this.channelInput || "" )
				.trim()
				.replace( /^https?:\/\/(?:www\.)?kick\.com\//i, "" )
				.replace( /^\/+|\/+$/g, "" );
			if ( !/^[a-zA-Z0-9_-]+$/.test( value ) ) { return; }
			set( this, "favorites", saveFavorites( [ ...getFavorites(), value ] ) );
			set( this, "channelInput", "" );
		},
		removeFavorite( slug ) {
			const remaining = getFavorites().filter( value => value !== slug );
			set( this, "favorites", saveFavorites( remaining ) );
		},
		openBrowser( slug ) {
			require( "nw.gui" ).Shell.openExternal( `https://kick.com/${slug}` );
		}
	}
});

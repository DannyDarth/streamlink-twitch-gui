import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";
import { getFavorites } from "ui/utils/kick-favorites";

export default Route.extend({
	model() {
		return [];
	},
	setupController( controller, model ) {
		this._super( controller, model );
		this.loadFavorites( controller );
	},
	async loadFavorites( controller ) {
		const favorites = getFavorites();
		setProperties( controller, { loading: true, error: null });
		try {
			const response = await fetch( "https://kick.com/stream/livestreams/en", { credentials: "omit" } );
			if ( !response.ok ) { throw new Error( "HTTP " + response.status ); }
			const data = await response.json();
			const rows = Array.isArray( data ) ? data : ( data && ( data.data || data.livestreams ) ) || [];
			set( controller, "streams", rows.filter( row => favorites.includes( ( ( row.channel && row.channel.slug ) || row.slug || "" ).toLowerCase() ) ).map( row => ({
				slug: ( row.channel && row.channel.slug ) || row.slug,
				title: row.session_title || row.title || ""
			})) );
		} catch ( error ) {
			set( controller, "error", "Could not check the public Kick directory: " + error.message );
		} finally {
			set( controller, "loading", false );
		}
	}
});

import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

export default Route.extend({
	async model() {
		return [];
	},
	setupController( controller, model ) {
		this._super( controller, model );
		this.loadDirectory( controller );
	},
	async loadDirectory( controller ) {
		setProperties( controller, { loading: true, error: null });
		try {
			const response = await fetch( "https://kick.com/stream/livestreams/en", { credentials: "omit" } );
			if ( !response.ok ) { throw new Error( "Kick live directory returned HTTP " + response.status ); }
			const data = await response.json();
			const rows = Array.isArray( data ) ? data : ( data && ( data.data || data.livestreams ) ) || [];
			set( controller, "streams", rows.map( row => ({
				slug: ( row.channel && row.channel.slug ) || row.slug,
				channel: ( row.channel && row.channel.slug ) || row.slug || "Unknown channel",
				title: row.session_title || row.title || "",
				viewers: row.viewer_count || row.viewers || 0,
				thumbnail: row.thumbnail && ( row.thumbnail.url || row.thumbnail )
			})).filter( row => row.slug ) );
		} catch ( error ) {
			set( controller, "error", "Kick live directory could not be loaded: " + error.message );
		} finally {
			set( controller, "loading", false );
		}
	}
});

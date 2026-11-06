import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

export default Route.extend({
	model() {
		return [];
	},
	setupController( controller, model ) {
		this._super( controller, model );
		this.loadGames( controller );
	},
	async loadGames( controller ) {
		setProperties( controller, { loading: true, error: null, games: [] });
		try {
			const response = await fetch(
				"https://kick.com/api/v1/categories-top",
				{ credentials: "omit" }
			);
			if ( !response.ok ) { throw new Error( `HTTP ${response.status}` ); }
			const data = await response.json();
			const rows = Array.isArray( data )
				? data
				: ( data && ( data.data || data.categories ) ) || [];
			if ( !Array.isArray( rows ) ) {
				throw new Error( "Unexpected category response" );
			}
			const games = rows.map( category => {
				const banner = category.banner || category.thumbnail || {};
				const image = typeof banner === "string"
					? banner : ( banner.src || banner.url || category.thumbnail_url || "" );
				const viewers = Number( category.viewers ?? category.viewer_count ?? 0 );
				return {
					name: category.name || category.slug || "",
					slug: category.slug || "",
					image,
					viewerCount: Number.isFinite( viewers ) ? viewers : 0,
					viewers: Number.isFinite( viewers ) ? viewers.toLocaleString() : "—"
				};
			}).filter( game => game.name );
			games.sort( ( a, b ) => b.viewerCount - a.viewerCount );
			set( controller, "games", games );
		} catch ( error ) {
			set( controller, "error", `Could not load Kick categories: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

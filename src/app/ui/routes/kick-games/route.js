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
		setProperties( controller, { loading: true, error: null });
		try {
			const response = await fetch(
				"https://kick.com/stream/livestreams/en",
				{ credentials: "omit" }
			);
			if ( !response.ok ) { throw new Error( `HTTP ${response.status}` ); }
			const data = await response.json();
			const rows = Array.isArray( data )
				? data
				: ( data && ( data.data || data.livestreams ) ) || [];
			const games = {};
			rows.forEach( row => {
				const category = row.categories && row.categories[0] || row.category;
				if ( !category ) { return; }
				const name = category.name || category.slug;
				if ( !name ) { return; }
				if ( !games[ name ] ) { games[ name ] = { name, channels: 0 }; }
				games[ name ].channels++;
			});
			const sorted = Object.values( games ).sort( ( a, b ) => b.channels - a.channels );
			set( controller, "games", sorted );
		} catch ( error ) {
			set( controller, "error", `Could not load Kick categories: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

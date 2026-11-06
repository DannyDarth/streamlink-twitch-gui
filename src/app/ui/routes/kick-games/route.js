import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";
import "./styles.less";

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
			// The public live directory is the same source used by Kick Streams.
			// Build categories from several pages rather than an unavailable categories endpoint.
			const categories = new Map();
			const seen = new Set();
			for ( let page = 1; page <= 5; page++ ) {
				const url = page === 1
					? "https://kick.com/stream/livestreams/en"
					: `https://kick.com/stream/livestreams/en?page=${page}`;
				let response;
				try {
					response = await fetch( url, { credentials: "omit" } );
					if ( !response.ok ) { throw new Error( `HTTP ${response.status}` ); }
				} catch ( error ) {
					if ( page === 1 ) { throw error; }
					break;
				}
				const data = await response.json();
				const rows = Array.isArray( data )
					? data : ( data && ( data.data || data.livestreams ) ) || [];
				if ( !Array.isArray( rows ) || !rows.length ) { break; }
				let added = 0;
				rows.forEach( row => {
					const channel = row.channel || {};
					const id = channel.slug || row.slug || row.id;
					if ( !id || seen.has( String( id ).toLowerCase() ) ) { return; }
					seen.add( String( id ).toLowerCase() );
					added++;
					const category = ( row.categories && row.categories[0] ) || row.category;
					if ( !category ) { return; }
					const name = category.name || category.slug;
					if ( !name ) { return; }
					const key = ( category.slug || name ).toLowerCase();
					const cover = category.banner || category.thumbnail || category.image || {};
					const image = typeof cover === "string"
						? cover : ( cover.src || cover.url || category.thumbnail_url || "" );
					const count = Number( row.viewer_count ?? row.viewers
						?? row.concurrent_viewers ?? row.current_viewers
						?? row.viewcount ?? ( row.livestream && row.livestream.viewcount ) ?? 0 );
					if ( !categories.has( key ) ) {
						categories.set( key, { name, slug: category.slug || "", image,
							viewerCount: 0, channels: 0 } );
					}
					const game = categories.get( key );
					game.channels++;
					if ( !game.image && image ) { game.image = image; }
					if ( Number.isFinite( count ) && count > 0 ) { game.viewerCount += count; }
				});
				if ( !added ) { break; }
			}
			const games = Array.from( categories.values() );
			games.forEach( game => {
				game.viewers = game.viewerCount.toLocaleString();
			});
			games.sort( ( a, b ) => b.viewerCount - a.viewerCount || b.channels - a.channels );
			set( controller, "games", games );
		} catch ( error ) {
			set( controller, "error", `Could not load Kick categories: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

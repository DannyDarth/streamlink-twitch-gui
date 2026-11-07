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
			for ( let page = 1; page <= 15; page++ ) {
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
						categories.set( key, { name, slug: category.slug || name, image,
							viewerCount: 0, channels: 0 } );
					}
					const game = categories.get( key );
					game.channels++;
					if ( !game.image && image ) { game.image = image; }
					if ( Number.isFinite( count ) && count > 0 ) { game.viewerCount += count; }
				});
				if ( !added ) { break; }
				const partial = Array.from( categories.values() );
				partial.forEach( game => {
					game.viewers = game.viewerCount.toLocaleString();
				});
				partial.sort( ( a, b ) => b.viewerCount - a.viewerCount
					|| b.channels - a.channels );
				set( controller, "games", partial );
				set( controller, "loading", false );
			}
			// Enrich directory categories with the public subcategory catalog.
			// Unlike livestream rows, subcategories include portrait banners and live viewers.
			try {
				for ( let page = 1; page <= 15; page++ ) {
					const response = await fetch(
						`https://kick.com/api/v1/subcategories?page=${page}&limit=32`,
						{ credentials: "omit" }
					);
					if ( !response.ok ) { break; }
						const payload = await response.json();
						const catalog = Array.isArray( payload ) ? payload
							: ( payload.data && ( Array.isArray( payload.data )
								? payload.data : payload.data.data ) )
							|| payload.subcategories || [];
						if ( !Array.isArray( catalog ) || !catalog.length ) { break; }
							catalog.forEach( item => {
								const name = item.name || item.slug;
								if ( !name ) { return; }
								const key = String( item.slug || name ).toLowerCase();
								const banner = item.banner || item.thumbnail || item.image || {};
								const image = typeof banner === "string" ? banner
									: ( banner.src || banner.url
										|| item.banner_url || item.thumbnail_url || "" );
								const count = Number( item.viewers ?? item.viewer_count );
								const game = categories.get( key ) || {
									name,
									slug: item.slug || name,
									image: "",
									viewerCount: 0,
									channels: 0
								};
								if ( image ) { game.image = image; }
								if ( Number.isFinite( count ) ) { game.viewerCount = count; }
								categories.set( key, game );
							});
							const partial = Array.from( categories.values() );
							partial.forEach( game => {
								game.viewers = game.viewerCount.toLocaleString();
							});
							partial.sort( ( a, b ) => b.viewerCount - a.viewerCount
								|| b.channels - a.channels );
							set( controller, "games", partial );
				}
			} catch ( error ) {
				// The live directory remains a usable fallback if catalog access fails.
			}
			const games = Array.from( categories.values() );
			games.forEach( game => {
				game.viewers = game.viewerCount.toLocaleString();
			});
			games.sort( ( a, b ) => b.viewerCount - a.viewerCount
				|| b.channels - a.channels );
			set( controller, "games", games );
		} catch ( error ) {
			set( controller, "error", `Could not load Kick categories: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

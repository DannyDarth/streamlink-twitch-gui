import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";
import "./styles.less";


// Kick returns banner artwork in several formats, including responsive URLs.
const coverUrl = item => {
	const banner = item.banner || item.thumbnail || item.image || {};
	if ( typeof banner === "string" ) { return banner; }
	return banner.src || banner.url || banner.responsive
		|| item.banner_url || item.thumbnail_url || item.responsive || "";
};
const categoryKey = item => String( item.slug || item.name || "" )
	.toLowerCase().replace( /[^a-z0-9]+/g, "-" ).replace( /^-|-$/g, "" );

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
			const catalogUrl = "https://kick.com/api/v1/subcategories?page=1&limit=32";
			const firstCatalog = fetch( catalogUrl, { credentials: "omit" } )
				.catch( () => null );
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
					const key = categoryKey( category );
					const image = coverUrl( category );
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
					const response = page === 1 ? await firstCatalog : await fetch(
						`https://kick.com/api/v1/subcategories?page=${page}&limit=32`,
						{ credentials: "omit" }
					);
					if ( !response || !response.ok ) { break; }
					const payload = await response.json();
					const catalog = Array.isArray( payload ) ? payload
						: ( payload.data && ( Array.isArray( payload.data )
							? payload.data : payload.data.data ) )
						|| payload.subcategories || [];
					if ( !Array.isArray( catalog ) || !catalog.length ) { break; }
					catalog.forEach( item => {
						const name = item.name || item.slug;
						if ( !name ) { return; }
						const key = categoryKey( item );
						const image = coverUrl( item );
						const count = Number( item.viewers ?? item.viewer_count );
						const game = categories.get( key ) || {
							name,
							slug: item.slug || name,
							image: "",
							viewerCount: 0,
							channels: 0
						};
						if ( image ) { game.image = image; }
						if ( Number.isFinite( count ) && count > 0 ) {
							game.viewerCount = count;
						}
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
			// Top categories expose portrait banner artwork for popular games.
			try {
				const response = await fetch(
					"https://kick.com/api/v1/categories-top", { credentials: "omit" }
				);
				if ( response.ok ) {
					const payload = await response.json();
					const rows = Array.isArray( payload ) ? payload
						: ( payload.data || payload.categories || [] );
					if ( Array.isArray( rows ) ) {
						rows.forEach( item => {
							const key = categoryKey( item );
							if ( !key ) { return; }
							const image = coverUrl( item );
							const count = Number( item.viewers ?? item.viewer_count );
							const game = categories.get( key ) || {
								name: item.name || item.slug, slug: item.slug || item.name,
								image: "", viewerCount: 0, channels: 0
							};
							if ( image ) { game.image = image; }
							if ( Number.isFinite( count ) && count > 0 ) {
								game.viewerCount = count;
							}
							categories.set( key, game );
						});
					}
				}
			} catch ( error ) {
				// Retain categories already loaded if top-category artwork is unavailable.
			}
			const games = Array.from( categories.values() );
			games.forEach( game => {
				game.viewers = game.viewerCount.toLocaleString();
			});
			games.sort( ( a, b ) => b.viewerCount - a.viewerCount
				|| b.channels - a.channels );
			set( controller, "games", games );
			// Recover missing artwork for visible categories without blocking the grid.
			const missing = games.slice( 0, 28 ).filter( game => !game.image );
			const recover = async () => {
				for ( let i = 0; i < missing.length; i += 4 ) {
					await Promise.all( missing.slice( i, i + 4 ).map( async game => {
						try {
							const slug = encodeURIComponent( game.slug );
							const response = await fetch(
								`https://kick.com/api/v1/subcategories/${slug}`,
								{ credentials: "omit" }
							);
							if ( !response.ok ) { return; }
							const payload = await response.json();
							const item = payload.data || payload;
							const image = coverUrl( item );
							if ( image ) {
								set( game, "image", image );
							}
						} catch ( error ) {
							// An unavailable cover must not delay the rest of the page.
						}
					}));
				}
			};
			recover();

		} catch ( error ) {
			set( controller, "error", `Could not load Kick categories: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

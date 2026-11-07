import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

// Ignore boolean live-status flags masquerading as viewer counts.
const countFrom = (...values) => {
	for ( const value of values ) {
		if ( typeof value !== "number" && typeof value !== "string" ) { continue; }
		if ( value === "" || value === null ) { continue; }
		const count = Number( value );
		if ( Number.isFinite( count ) && count > 0 ) { return count; }
	}
	return null;
};

export default Route.extend({
	model( params ) {
		return params.category_slug;
	},
	setupController( controller, slug ) {
		this._super( controller, slug );
		this.loadCategory( controller, slug );
	},
	async loadCategory( controller, slug ) {
		setProperties( controller, {
			loading: true, error: null, streams: [],
			categorySlug: slug, categoryName: slug.replace( /-/g, " " )
		});
		try {
			const streams = [];
			const seen = new Set();
			for ( let page = 1; page <= 20; page++ ) {
				const base = "https://kick.com/stream/livestreams/en";
				const category = encodeURIComponent( slug );
				const url = `${base}?subcategory=${category}&page=${page}`;
				const response = await fetch( url, { credentials: "omit" } );
				if ( !response.ok ) {
					if ( page === 1 ) { throw new Error( `HTTP ${response.status}` ); }
					break;
				}
				const payload = await response.json();
				const rows = Array.isArray( payload ) ? payload
					: ( payload && ( payload.data || payload.livestreams ) ) || [];
				if ( !Array.isArray( rows ) || !rows.length ) { break; }
				let newRows = 0;
				rows.forEach( row => {
					const channel = row.channel || {};
					const channelSlug = channel.slug || row.slug;
					if ( !channelSlug || seen.has( channelSlug ) ) { return; }
					seen.add( channelSlug );
					newRows++;
					const category = ( row.categories && row.categories[0] ) || row.category || {};
					const key = String( category.slug || category.name || "" ).toLowerCase();
					if ( key !== slug.toLowerCase() ) { return; }
					const thumbnail = row.thumbnail || row.thumbnail_url
						|| row.stream_thumbnail || row.livestream?.thumbnail || {};
					const image = typeof thumbnail === "string" ? thumbnail
						: ( thumbnail.src || thumbnail.url || "" );
					const live = row.livestream || {};
					const livestreamId = live.id || row.livestream_id || row.stream_id || null;
					const count = countFrom(
						row.viewer_count, row.viewers, row.concurrent_viewers,
						row.current_viewers, row.viewcount, live.viewer_count,
						live.viewers, live.viewcount, live.concurrent_viewers
					);
					streams.push({
						slug: channelSlug,
						livestreamId: livestreamId || null,
						channel: ( channel.user && channel.user.username )
							|| channel.slug || channelSlug,
						title: row.session_title || row.title || "",
						thumbnail: image,
						viewerCount: count,
						viewers: count === null ? "—" : count.toLocaleString(),
						category: category.name || ""
					});
					if ( category.name ) { set( controller, "categoryName", category.name ); }
				});
				if ( streams.length ) {
					streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
					set( controller, "streams", streams.slice() );
					set( controller, "loading", false );
				}
				if ( !newRows ) { break; }
			}
			// Kick's website fetches viewer counts by livestream ID in batches.
			const withIds = streams.filter( stream => stream.livestreamId );
			window.console.info( "[Kick viewers] Category stream IDs", {
				streams: streams.length, withIds: withIds.length,
				sample: withIds.slice( 0, 3 ).map( stream => stream.livestreamId )
			} );
			for ( let i = 0; i < withIds.length; i += 40 ) {
				const batch = withIds.slice( i, i + 40 );
				const params = batch.map( stream =>
					`ids[]=${encodeURIComponent( stream.livestreamId )}`
				).join( "&" );
				try {
					const response = await fetch(
						`https://kick.com/current-viewers?${params}`,
						{ credentials: "omit" }
					);
					if ( !response.ok ) {
						window.console.warn( "[Kick viewers] HTTP", response.status );
						continue;
					}
					const payload = await response.json();
					if ( !Array.isArray( payload ) ) {
						window.console.warn( "[Kick viewers] Unexpected response format" );
						continue;
					}
					const byId = new Map( batch.map( stream =>
						[ String( stream.livestreamId ), stream ]
					) );
					let matched = 0;
					payload.forEach( item => {
						const stream = byId.get( String( item.livestream_id ) );
						if ( !stream ) { return; }
						matched++;
						const count = item.show_view_count === false
							? null : countFrom( item.viewers );
						set( stream, "viewerCount", count );
						set( stream, "viewers", count === null ? "—" : count.toLocaleString() );
					});
					window.console.info( "[Kick viewers] Batch result", {
						requested: batch.length, returned: payload.length, matched
					} );
				} catch ( error ) {
					window.console.warn( "[Kick viewers] Request failed", error );
				}
			}
			set( controller, "streams", streams.slice() );
			// Only fetch extra channel data when the directory lacks a thumbnail.
			for ( let i = 0; i < streams.length; i += 5 ) {
				await Promise.all( streams.slice( i, i + 5 ).map( async stream => {
					if ( stream.thumbnail && stream.viewerCount !== null ) { return; }
					const channelSlug = encodeURIComponent( stream.slug );
					const base = `https://kick.com/api/v2/channels/${channelSlug}`;
					const applyThumbnail = live => {
						if ( !live ) { return; }
						const count = countFrom(
							live.viewer_count, live.viewers, live.viewcount,
							live.concurrent_viewers
						);
						if ( count !== null ) {
							set( stream, "viewerCount", count );
							set( stream, "viewers", count.toLocaleString() );
						}
						const cover = live.thumbnail || live.thumbnail_url || {};
						const image = typeof cover === "string"
							? cover : ( cover.src || cover.url || "" );
						if ( image ) { set( stream, "thumbnail", image ); }
					};
					try {
						const response = await fetch(
							`${base}/livestream`, { credentials: "omit" }
						);
						if ( response.ok ) {
							const payload = await response.json();
							applyThumbnail( payload.data || payload );
						}
					} catch ( error ) {
						// Keep the channel available if its thumbnail fails.
					}
					if ( stream.thumbnail && stream.viewerCount !== null ) { return; }
					try {
						const response = await fetch( base, { credentials: "omit" } );
						if ( !response.ok ) { return; }
						const payload = await response.json();
						const profile = payload.data || payload;
						applyThumbnail( profile.livestream || profile.stream || profile );
					} catch ( error ) {
						// Missing artwork must not prevent playback.
					}
				}));
			}
			streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
			set( controller, "streams", streams );
		} catch ( error ) {
			set( controller, "error", `Could not load category streams: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

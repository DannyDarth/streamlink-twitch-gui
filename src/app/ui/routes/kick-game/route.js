import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

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
					const count = row.viewer_count ?? row.viewers
						?? row.concurrent_viewers ?? row.current_viewers
						?? row.viewcount ?? ( row.livestream && row.livestream.viewcount );
					streams.push({
						slug: channelSlug,
						channel: ( channel.user && channel.user.username )
							|| channel.slug || channelSlug,
						title: row.session_title || row.title || "",
						thumbnail: image,
						viewerCount: Number( count ) > 0 ? Number( count ) : null,
						viewers: Number( count ) > 0
							? Number( count ).toLocaleString() : "—",
						category: category.name || ""
					});
					if ( category.name ) { set( controller, "categoryName", category.name ); }
				});
				if ( streams.length ) {
					set( controller, "streams", streams.slice() );
					set( controller, "loading", false );
				}
				if ( !newRows ) { break; }
			}
			// Only fetch extra channel data when the directory lacks a thumbnail.
			for ( let i = 0; i < streams.length; i += 5 ) {
				await Promise.all( streams.slice( i, i + 5 ).map( async stream => {
					if ( stream.thumbnail ) { return; }
					const channelSlug = encodeURIComponent( stream.slug );
					const base = `https://kick.com/api/v2/channels/${channelSlug}`;
					const applyThumbnail = live => {
						if ( !live ) { return; }
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
					if ( stream.thumbnail ) { return; }
					try {
						const response = await fetch( base, { credentials: "omit" } );
						if ( !response.ok ) { return; }
						const payload = await response.json();
						const profile = payload.data || payload;
						applyThumbnail( profile.livestream );
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

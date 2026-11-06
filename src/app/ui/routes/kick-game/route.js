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
			for ( let page = 1; page <= 5; page++ ) {
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
						viewerCount: Number( count ) || 0,
						viewers: ( count === null || count === undefined )
							? "—" : Number( count ).toLocaleString(),
						category: category.name || ""
					});
					if ( category.name ) { set( controller, "categoryName", category.name ); }
				});
				if ( !newRows ) { break; }
			}
			// Fill in live thumbnails and viewer counts from each channel's
			// current livestream, in small batches to avoid request bursts.
			for ( let i = 0; i < streams.length; i += 5 ) {
				await Promise.all( streams.slice( i, i + 5 ).map( async stream => {
					try {
						const channelSlug = encodeURIComponent( stream.slug );
						const url = `https://kick.com/api/v2/channels/${channelSlug}/livestream`;
						const response = await fetch( url, { credentials: "omit" } );
						if ( !response.ok ) { return; }
						const payload = await response.json();
						const live = payload.data || payload;
						if ( !live || !live.id ) { return; }
						const cover = live.thumbnail || {};
						const image = typeof cover === "string"
							? cover : ( cover.src || cover.url || "" );
						if ( image ) { set( stream, "thumbnail", image ); }
						const count = live.viewers ?? live.viewcount ?? live.viewer_count;
						if ( count !== null && count !== undefined ) {
							set( stream, "viewers", Number( count ).toLocaleString() );
							set( stream, "viewerCount", Number( count ) );
						}
						if ( live.session_title ) {
							set( stream, "title", live.session_title );
						}
					} catch ( error ) {
						// Keep the stream card visible when enrichment fails.
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

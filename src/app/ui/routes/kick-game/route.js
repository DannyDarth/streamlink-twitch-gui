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
			loading: true, error: null, streams: [], diagnostic: "",
			categorySlug: slug, categoryName: slug.replace( /-/g, " " )
		});
		try {
			const streams = [];
			const seen = new Set();
			const diagnostics = [];
			const fields = data => {
				if ( !data || typeof data !== "object" ) { return "none"; }
				return [ "viewers", "viewcount", "viewer_count",
					"concurrent_viewers", "current_viewers" ]
					.map( key => `${key}:${typeof data[key]}=${String( data[key] )}` )
					.join( ", " );
			};
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
					if ( diagnostics.length === 0 ) {
						diagnostics.push( `directory: ${fields( row )}` );
					}
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
				if ( !newRows ) { break; }
			}
			// Use the same livestream lookup as Followed Channels.
			// Fetch the channel profile only when details remain missing.
			for ( let i = 0; i < streams.length; i += 5 ) {
				await Promise.all( streams.slice( i, i + 5 ).map( async stream => {
					const channelSlug = encodeURIComponent( stream.slug );
					const base = `https://kick.com/api/v2/channels/${channelSlug}`;
					const applyLive = live => {
						if ( !live ) { return; }
						const count = live.viewers ?? live.viewcount
							?? live.viewer_count ?? live.concurrent_viewers;
						if ( Number( count ) > 0 ) {
							set( stream, "viewerCount", Number( count ) );
							set( stream, "viewers", Number( count ).toLocaleString() );
						}
						const cover = live.thumbnail || live.thumbnail_url || {};
						const image = typeof cover === "string"
							? cover : ( cover.src || cover.url || "" );
						if ( image && !stream.thumbnail ) {
							set( stream, "thumbnail", image );
						}
						const title = live.session_title || live.title;
						if ( title && !stream.title ) { set( stream, "title", title ); }
					};
					try {
						const response = await fetch(
							`${base}/livestream`, { credentials: "omit" }
						);
						if ( diagnostics.length < 3 ) {
							diagnostics.push( `livestream HTTP ${response.status}` );
						}
						if ( response.ok ) {
							const payload = await response.json();
							const live = payload.data || payload;
							if ( diagnostics.length < 4 ) {
								diagnostics.push( `livestream: ${fields( live )}` );
							}
							applyLive( live );
						}
					} catch ( error ) {
						// The channel profile can still provide live details.
					}
					if ( stream.viewerCount && stream.thumbnail ) { return; }
					try {
						const response = await fetch( base, { credentials: "omit" } );
						if ( !response.ok ) { return; }
						const payload = await response.json();
						const profile = payload.data || payload;
						if ( diagnostics.length < 6 ) {
							diagnostics.push( `profile: ${fields( profile.livestream )}` );
						}
						applyLive( profile.livestream );
					} catch ( error ) {
						// Missing metadata must not prevent playback.
					}
				}));
			}
			streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
			set( controller, "streams", streams );
			set( controller, "diagnostic", diagnostics.slice( 0, 6 ).join( " | " ) );
		} catch ( error ) {
			set( controller, "error", `Could not load category streams: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

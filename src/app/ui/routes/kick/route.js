import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

export default Route.extend({
	queryParams: {
		query: { refreshModel: true }
	},
	model( params ) {
		return params.query || "";
	},
	setupController( controller, model ) {
		this._super( controller, model );
		if ( model ) {
			this.loadChannel( controller, model );
		} else {
			this.loadDirectory( controller );
		}
	},
	async loadChannel( controller, query ) {
		setProperties( controller, { loading: true, error: null, streams: [] });
		try {
			const slug = query.trim().replace( /^@/, "" );
			const response = await fetch(
				`https://kick.com/api/v2/channels/${encodeURIComponent( slug )}/livestream`,
				{ credentials: "omit" }
			);
			if ( !response.ok ) {
				throw new Error( `Kick channel returned HTTP ${response.status}` );
			}
			const result = await response.json();
			const live = result.data || result;
			if ( !live || !live.id ) {
				set( controller, "error", `No live stream found for ${slug}.` );
				return;
			}
			const thumbnail = live.thumbnail || {};
			set( controller, "streams", [{
				slug,
				channel: slug,
				title: live.session_title || live.title || "",
				viewers: Number( live.viewers ?? 0 ).toLocaleString(),
				thumbnail: thumbnail.src || thumbnail.url || "",
				category: ( live.category && live.category.name ) || ""
			}]);
		} catch ( error ) {
			set( controller, "error", `Kick search failed: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	},
	async loadDirectory( controller ) {
		setProperties( controller, { loading: true, error: null });
		try {
			const rows = [];
			const seen = new Set();
			for ( let page = 1; page <= 5; page++ ) {
				const url = page === 1
					? "https://kick.com/stream/livestreams/en"
					: `https://kick.com/stream/livestreams/en?page=${page}`;
				let response;
				try {
					response = await fetch( url, { credentials: "omit" } );
					if ( !response.ok ) {
						throw new Error( `HTTP ${response.status}` );
					}
				} catch ( error ) {
					if ( page === 1 ) { throw error; }
					break;
				}
				const data = await response.json();
				const batch = Array.isArray( data )
					? data
					: ( data && ( data.data || data.livestreams ) ) || [];
				if ( !Array.isArray( batch ) || !batch.length ) { break; }
				let added = 0;
				batch.forEach( row => {
					const channel = row.channel || {};
					const slug = channel.slug || row.slug;
					if ( slug && !seen.has( slug.toLowerCase() ) ) {
						seen.add( slug.toLowerCase() );
						rows.push( row );
						added++;
					}
				});
				if ( !added || rows.length >= 150 ) { break; }
			}
			const streams = rows.map( row => {
				const channel = row.channel || {};
				const slug = channel.slug || row.slug;
				const thumbnail = row.thumbnail || row.thumbnail_url || row.stream_thumbnail || {};
				const image = typeof thumbnail === "string"
					? thumbnail
					: ( thumbnail.url || thumbnail.src || "" );
				const viewers = row.viewer_count
					?? row.viewers
					?? row.concurrent_viewers
					?? row.current_viewers
					?? row.viewcount
					?? ( row.livestream && row.livestream.viewcount )
					?? null;
				return {
					slug,
					channel: ( channel.user && channel.user.username )
						|| channel.slug
						|| slug
						|| "Unknown channel",
					title: row.session_title || row.title || "",
					viewerCount: Number.isFinite( Number( viewers ) ) && viewers !== null
						? Number( viewers ) : -1,
					viewers: viewers === null || viewers === undefined
						? "—"
						: Number( viewers ).toLocaleString(),
					thumbnail: image,
					category: ( row.categories && row.categories[0] && row.categories[0].name )
						|| ( row.category && row.category.name )
						|| ""
				};
			}).filter( row => row.slug );
			await this.loadViewerCounts( streams );
			streams.sort( ( a, b ) => b.viewerCount - a.viewerCount
				|| a.channel.localeCompare( b.channel ) );
			set( controller, "streams", streams );
		} catch ( error ) {
			set( controller, "error", `Kick live directory could not be loaded: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	},
	async loadViewerCounts( streams ) {
		const missing = streams.filter( stream => stream.viewerCount < 0 ).slice( 0, 100 );
		for ( let i = 0; i < missing.length; i += 5 ) {
			await Promise.all( missing.slice( i, i + 5 ).map( async stream => {
				try {
					const response = await fetch(
						`https://kick.com/api/v2/channels/${encodeURIComponent( stream.slug )}/livestream`,
						{ credentials: "omit" }
					);
					if ( !response.ok ) { return; }
					const data = await response.json();
					const live = data.data || data;
					const count = live.viewers ?? live.viewcount ?? live.viewer_count;
					if ( count !== null && count !== undefined
						&& Number.isFinite( Number( count ) ) ) {
						set( stream, "viewers", Number( count ).toLocaleString() );
						set( stream, "viewerCount", Number( count ) );
					}
				} catch ( error ) {
					// Counts are optional; keep the directory usable.
				}
			}));
		}
	}
});

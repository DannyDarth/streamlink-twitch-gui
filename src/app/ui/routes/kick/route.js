import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

// Kick's directory and channel APIs return thumbnails in different shapes.
const thumbnailUrl = (...candidates) => {
	for ( const candidate of candidates ) {
		if ( !candidate ) { continue; }
		const value = typeof candidate === "string" ? candidate
			: ( candidate.src || candidate.url || candidate.responsive || "" );
		if ( typeof value !== "string" ) { continue; }
		const url = value.split( "," )[0].trim().split( /\s+/ )[0];
		if ( url.startsWith( "https://" ) || url.startsWith( "http://" ) ) { return url; }
	}
	return "";
};

const viewerCount = (...candidates) => {
	for ( const candidate of candidates ) {
		if ( candidate === null || candidate === undefined || candidate === "" ) { continue; }
		const value = Number( candidate );
		if ( Number.isFinite( value ) && value > 0 ) { return value; }
	}
	return null;
};

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
			const viewers = viewerCount( live.viewer_count, live.viewers, live.viewcount, live.concurrent_viewers );
			set( controller, "streams", [{
				slug,
				channel: slug,
				title: live.session_title || live.title || "",
				viewers: viewers === null ? "—" : viewers.toLocaleString(),
				thumbnail: thumbnailUrl( live.thumbnail, live.thumbnail_url, live.stream_thumbnail ),
				category: ( live.category && live.category.name ) || ""
			}]);
		} catch ( error ) {
			set( controller, "error", `Kick search failed: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	},
	async loadDirectory( controller, append = false ) {
		if ( controller.loadingMore ) { return; }
		if ( !append ) {
			setProperties( controller, { loading: true, error: null, streams: [],
				nextPage: 1, hasMore: true });
		} else {
			set( controller, "loadingMore", true );
		}
		try {
			const streams = append ? controller.streams.slice() : [];
			const seen = new Set( streams.map( stream => stream.slug ) );
			const firstPage = append ? controller.nextPage : 1;
			for ( let page = firstPage; page < firstPage + 5 && page <= 15; page++ ) {
				const url = page === 1
					? "https://kick.com/stream/livestreams/en"
					: `https://kick.com/stream/livestreams/en?page=${page}`;
				const response = await fetch( url, { credentials: "omit" } );
				if ( !response.ok ) {
					if ( page === 1 ) {
						throw new Error( `Kick directory HTTP ${response.status}` );
					}
					break;
				}
				const data = await response.json();
				const rows = Array.isArray( data )
					? data
					: ( data && ( data.data || data.livestreams ) ) || [];
				if ( !Array.isArray( rows ) || !rows.length ) {
					set( controller, "hasMore", false );
					break;
				}
				const batch = rows.map( row => {
					const channel = row.channel || {};
					const slug = channel.slug || row.slug;
					const live = row.livestream || channel.livestream || {};
					const image = thumbnailUrl(
						row.thumbnail, row.thumbnail_url, row.stream_thumbnail,
						live.thumbnail, live.thumbnail_url, live.stream_thumbnail,
						channel.thumbnail, channel.thumbnail_url
					);
					const viewers = viewerCount(
						row.viewer_count, row.viewers, row.concurrent_viewers,
						row.current_viewers, row.viewcount, live.viewer_count,
						live.viewers, live.viewcount, live.concurrent_viewers,
						channel.viewer_count
					);
					return {
						slug,
						channel: ( channel.user && channel.user.username )
							|| channel.slug
							|| slug
							|| "Unknown channel",
						title: row.session_title || row.title || "",
						viewerCount: viewers,
						viewers: viewers === null ? "—" : viewers.toLocaleString(),
						thumbnail: image,
						category: ( row.categories && row.categories[0] && row.categories[0].name )
							|| ( row.category && row.category.name )
							|| ""
					};
				}).filter( row => row.slug && !seen.has( row.slug ) );
				batch.forEach( stream => {
					seen.add( stream.slug );
					streams.push( stream );
				});
				streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
				set( controller, "streams", streams.slice() );
				set( controller, "loading", false );
				set( controller, "nextPage", page + 1 );
				if ( page === 15 ) {
					set( controller, "hasMore", false );
					break;
				}
			}
		} catch ( error ) {
			set( controller, "error", `Kick live directory could not be loaded: ${error.message}` );
		} finally {
			set( controller, "loading", false );
			set( controller, "loadingMore", false );
		}
	},
	actions: {
		loadMore() {
			this.loadDirectory( this.controller, true );
		}
	}
});

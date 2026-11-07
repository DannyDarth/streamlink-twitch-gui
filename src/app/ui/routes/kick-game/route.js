import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

// Ignore boolean live-status flags and nonpositive placeholder counts.
const countFrom = (...values) => {
	for ( const value of values ) {
		if ( typeof value !== "number" && typeof value !== "string" ) { continue; }
		if ( value === "" || value === null ) { continue; }
		const count = Number( value );
		if ( Number.isFinite( count ) && count > 0 ) { return count; }
	}
	return null;
};

// Fetch and validate a single Kick directory page.
const fetchDirectoryPage = async url => {
	const response = await fetch( url, { credentials: "omit", cache: "no-store" } );
	if ( !response.ok ) { throw new Error( `HTTP ${response.status}` ); }
	const payload = await response.json();
	const rows = Array.isArray( payload ) ? payload
		: ( payload && ( payload.data || payload.livestreams ) ) || [];
	if ( !Array.isArray( rows ) ) { throw new Error( "Unexpected directory response" ); }
	return rows;
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
			categorySlug: slug, categoryName: slug.replace( /-/g, " " ),
			viewerDiagnostics: "Waiting for directory response..."
		});
		try {
			const streams = [];
			const seen = new Set();
			let pagesLoaded = 0;
			let stopReason = "page limit";
			const pageSizes = [];
			for ( let page = 1; page <= 20; page++ ) {
				const base = "https://kick.com/stream/livestreams/en";
				const category = encodeURIComponent( slug );
				const url = `${base}?subcategory=${category}&page=${page}`;
				let rows = null;
				let lastError = null;
				for ( let attempt = 0; attempt < 2; attempt++ ) {
					try {
						rows = await fetchDirectoryPage( url );
						if ( rows.length ) { break; }
					} catch ( error ) {
						lastError = error;
					}
				}
				if ( !rows || !rows.length ) {
					stopReason = lastError ? lastError.message : "empty page";
					if ( page === 1 && lastError ) { throw lastError; }
					break;
				}
				pagesLoaded++;
				pageSizes.push( rows.length );
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
					const live = row.livestream || {};
					const thumbnail = row.thumbnail || row.thumbnail_url
						|| row.stream_thumbnail || live.thumbnail || channel.thumbnail || {};
					const image = typeof thumbnail === "string" ? thumbnail
						: ( thumbnail.src || thumbnail.url || thumbnail.responsive || "" )
							.split( "," )[0].trim().split( /\s+/ )[0];
					const livestreamId = live.id || row.livestream_id || row.stream_id || null;
					const count = countFrom(
						row.viewer_count, row.concurrent_viewers,
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
				if ( !newRows ) {
					stopReason = "duplicate page";
					break;
				}
			}

			// Resolve livestream IDs and counts using the verified channel info API.
			let resolved = 0;
			let failed = 0;
			let infoSample = "none";
			for ( let i = 0; i < streams.length; i += 5 ) {
				await Promise.all( streams.slice( i, i + 5 ).map( async stream => {
					const channelSlug = encodeURIComponent( stream.slug );
					const url = `https://kick.com/api/v2/channels/${channelSlug}/info`;
					try {
						const response = await fetch( url, { credentials: "omit" } );
						if ( !response.ok ) { failed++; return; }
						const payload = await response.json();
						const profile = payload.data || payload;
						const live = profile.livestream;
						if ( !live || !live.id ) { return; }
						set( stream, "livestreamId", live.id );
						const count = live.show_view_count === false
							? null : countFrom( live.viewer_count );
						// Keep higher directory counts if channel info is stale.
						const previous = stream.viewerCount;
						const bestCount = count === null ? previous
							: previous === null ? count : Math.max( previous, count );
						if ( infoSample === "none" ) {
							infoSample = `${stream.slug}: ${String( live.viewer_count )}`;
						}
						set( stream, "viewerCount", bestCount );
						set( stream, "viewers",
							bestCount === null ? "—" : bestCount.toLocaleString() );
						const cover = live.thumbnail || {};
						const image = ( typeof cover === "string"
							? cover : ( cover.url || cover.src || cover.responsive || "" ) )
							.split( "," )[0].trim().split( /\s+/ )[0];
						if ( !stream.thumbnail && image ) {
							set( stream, "thumbnail", image );
						}
						resolved++;
					} catch ( error ) {
						failed++;
					}
				}));
				set( controller, "viewerDiagnostics",
					`Streams: ${streams.length}; IDs: ${resolved}; failed: ${failed}` );
			}
			// The channel-info endpoint sometimes returns zero for active streams.
			// Try Kick's per-livestream endpoint only for unresolved counts.
			let recovered = 0;
			let lookupFailed = 0;
			const unresolved = streams.filter( stream =>
				stream.viewerCount === null && stream.livestreamId
			);
			for ( let i = 0; i < unresolved.length; i += 5 ) {
				await Promise.all( unresolved.slice( i, i + 5 ).map( async stream => {
					try {
						const id = String( stream.livestreamId );
						const url = `https://kick.com/current-viewers?ids[]=${encodeURIComponent( id )}`;
						const response = await fetch( url, { credentials: "omit" } );
						if ( !response.ok ) { lookupFailed++; return; }
						const payload = await response.json();
						const entry = Array.isArray( payload )
							? payload.find( row => String( row.livestream_id ) === id ) : null;
						if ( !entry || entry.show_view_count === false ) { return; }
						const count = countFrom( entry.viewers );
						if ( count === null ) { return; }
						set( stream, "viewerCount", count );
						set( stream, "viewers", count.toLocaleString() );
						recovered++;
					} catch ( error ) {
						lookupFailed++;
					}
				}));
			}
			streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
			set( controller, "streams", streams.slice() );
			set( controller, "viewerDiagnostics",
				`Streams: ${streams.length}; pages: ${pagesLoaded};`
				+ ` page sizes: ${pageSizes.join( "," )}; stop: ${stopReason};`
				+ ` resolved: ${resolved}; failed: ${failed};`
				+ ` recovered: ${recovered}; lookup failed: ${lookupFailed};`
				+ ` sample: ${infoSample}` );
		} catch ( error ) {
			set( controller, "error", `Could not load category streams: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

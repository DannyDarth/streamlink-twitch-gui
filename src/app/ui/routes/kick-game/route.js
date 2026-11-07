import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

// Ignore boolean live-status flags masquerading as viewer counts.
const countFrom = (...values) => {
	for ( const value of values ) {
		if ( typeof value !== "number" && typeof value !== "string" ) { continue; }
		if ( value === "" || value === null ) { continue; }
		const count = Number( value );
		if ( Number.isFinite( count ) && count >= 0 ) { return count; }
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
			categorySlug: slug, categoryName: slug.replace( /-/g, " " ),
			viewerDiagnostics: "Waiting for directory response..."
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
				if ( !newRows ) { break; }
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
						if ( infoSample === "none" ) {
							infoSample = `${stream.slug}: ${String( live.viewer_count )}`;
						}
						set( stream, "viewerCount", count );
						set( stream, "viewers", count === null ? "—" : count.toLocaleString() );
						const cover = live.thumbnail || {};
						const image = typeof cover === "string"
							? cover : ( cover.url || cover.src || "" );
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
			// Refresh counts in batches after resolving the real livestream IDs.
			const withIds = streams.filter( stream => stream.livestreamId );
			let matched = 0;
			let batchStatus = "not requested";
			let accepted = 0;
			let rejected = 0;
			let infoPositive = streams.filter( stream => stream.viewerCount > 0 ).length;
			let batchPositive = 0;
			let batchSample = "none";
			for ( let i = 0; i < withIds.length; i += 10 ) {
				const batch = withIds.slice( i, i + 10 );
				const params = batch.map( stream =>
					`ids[]=${encodeURIComponent( stream.livestreamId )}`
				).join( "&" );
				try {
					const response = await fetch(
						`https://kick.com/current-viewers?${params}`,
						{ credentials: "omit" }
					);
					batchStatus = `HTTP ${response.status}`;
					if ( !response.ok ) { rejected++; continue; }
					accepted++;
					const payload = await response.json();
					if ( !Array.isArray( payload ) ) {
						batchStatus = "Unexpected response format";
						continue;
					}
					batchStatus = `HTTP 200; returned ${payload.length}`;
					const byId = new Map( batch.map( stream =>
						[ String( stream.livestreamId ), stream ]
					) );
					payload.forEach( item => {
						const stream = byId.get( String( item.livestream_id ) );
						if ( !stream ) { return; }
						matched++;
						const count = item.show_view_count === false
							? null : countFrom( item.viewers );
						if ( count > 0 ) { batchPositive++; }
						if ( batchSample === "none" ) {
							batchSample = `${stream.slug}: ${String( item.viewers )}`;
						}
						// Keep a positive channel count if the batch endpoint reports zero.
						if ( count === 0 && stream.viewerCount > 0 ) { return; }
						set( stream, "viewerCount", count );
						set( stream, "viewers", count === null ? "—" : count.toLocaleString() );
					});
				} catch ( error ) {
					batchStatus = `Request error: ${error.message}`;
				}
			}
			set( controller, "viewerDiagnostics",
				`Streams: ${streams.length}; IDs: ${resolved};`
				+ ` matched: ${matched}; failed: ${failed};`
				+ ` batches OK: ${accepted}; rejected: ${rejected}; ${batchStatus};`
				+ ` info >0: ${infoPositive}; batch >0: ${batchPositive};`
				+ ` info sample: ${infoSample}; batch sample: ${batchSample}` );
			set( controller, "streams", streams.slice() );
			streams.sort( ( a, b ) => ( b.viewerCount || 0 ) - ( a.viewerCount || 0 ) );
			set( controller, "streams", streams );
		} catch ( error ) {
			set( controller, "error", `Could not load category streams: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

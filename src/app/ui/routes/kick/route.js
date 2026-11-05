import Route from "@ember/routing/route";
import { set, setProperties } from "@ember/object";

export default Route.extend({
	model() {
		return [];
	},
	setupController( controller, model ) {
		this._super( controller, model );
		this.loadDirectory( controller );
	},
	async loadDirectory( controller ) {
		setProperties( controller, { loading: true, error: null });
		try {
			const response = await fetch(
				"https://kick.com/stream/livestreams/en",
				{ credentials: "omit" }
			);
			if ( !response.ok ) {
				throw new Error( `Kick live directory returned HTTP ${response.status}` );
			}
			const data = await response.json();
			const rows = Array.isArray( data )
				? data
				: ( data && ( data.data || data.livestreams ) ) || [];
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
					viewers: viewers === null || viewers === undefined
						? "—"
						: Number( viewers ).toLocaleString(),
					thumbnail: image,
					category: ( row.categories && row.categories[0] && row.categories[0].name )
						|| ( row.category && row.category.name )
						|| ""
				};
			}).filter( row => row.slug );
			set( controller, "streams", streams );
			await this.loadViewerCounts( streams );
		} catch ( error ) {
			set( controller, "error", `Kick live directory could not be loaded: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	},
	async loadViewerCounts( streams ) {
		const missing = streams.filter( stream => stream.viewers === "—" ).slice( 0, 30 );
		for ( let i = 0; i < missing.length; i += 5 ) {
			await Promise.all( missing.slice( i, i + 5 ).map( async stream => {
				try {
					const response = await fetch(
						`https://kick.com/api/v2/channels/${encodeURIComponent( stream.slug )}/livestream`,
						{ credentials: "omit" }
					);
					if ( !response.ok ) { return; }
					const data = await response.json();
					const count = data.viewers ?? data.viewcount ?? data.viewer_count;
					if ( count !== null && count !== undefined && Number.isFinite( Number( count ) ) ) {
						set( stream, "viewers", Number( count ).toLocaleString() );
					}
				} catch ( error ) {
					// Counts are optional; keep the directory usable.
				}
			}));
		}
	}
});

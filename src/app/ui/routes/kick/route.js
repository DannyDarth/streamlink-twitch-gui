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
			set( controller, "streams", rows.map( row => {
				const channel = row.channel || {};
				const slug = channel.slug || row.slug;
				const thumbnail = row.thumbnail || row.thumbnail_url || row.stream_thumbnail || {};
				const image = typeof thumbnail === "string"
					? thumbnail
					: ( thumbnail.url || thumbnail.src || "" );
				const viewers = row.viewer_count ?? row.viewers ??
					row.concurrent_viewers ?? row.current_viewers ?? 0;
				return {
					slug,
					channel: channel.user && channel.user.username || channel.slug || slug || "Unknown channel",
					title: row.session_title || row.title || "",
					viewers: Number( viewers ).toLocaleString(),
					thumbnail: image,
					category: row.categories && row.categories[0] && row.categories[0].name ||
						row.category && row.category.name || ""
				};
			}).filter( row => row.slug ) );
		} catch ( error ) {
			set( controller, "error", `Kick live directory could not be loaded: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

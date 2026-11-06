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
				const url = page === 1
					? "https://kick.com/stream/livestreams/en"
					: `https://kick.com/stream/livestreams/en?page=${page}`;
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
						|| row.stream_thumbnail || {};
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
						viewers: count == null ? "—" : Number( count ).toLocaleString(),
						category: category.name || ""
					});
					if ( category.name ) { set( controller, "categoryName", category.name ); }
				});
				if ( !newRows ) { break; }
			}
			set( controller, "streams", streams );
		} catch ( error ) {
			set( controller, "error", `Could not load category streams: ${error.message}` );
		} finally {
			set( controller, "loading", false );
		}
	}
});

import KickController from "../kick/controller";
import { set } from "@ember/object";

const imageUrl = value => {
	if ( typeof value === "string" ) { return value; }
	if ( !value || typeof value !== "object" ) { return ""; }
	const url = value.url || value.src || value.link || value.hd_link
		|| value.responsive || "";
	return typeof url === "string" ? url.split( "," )[0].trim().split( /\\s+/ )[0] : "";
};

const fetchThumbnail = async ( slug, endpoint ) => {
	const response = await fetch(
		`https://kick.com/api/v2/channels/${slug}/${endpoint}`,
		{ credentials: "omit" }
	);
	if ( !response.ok ) { return ""; }
	const payload = await response.json();
	const data = payload && ( payload.data || payload );
	const live = endpoint === "info" ? data && data.livestream : data;
	return imageUrl( live && ( live.thumbnail || live.thumbnail_url ) );
};

export default KickController.extend({
	categoryName: "",
	categorySlug: "",
	actions: {
		async thumbnailError( stream ) {
			if ( stream.thumbnailFallbackTried ) {
				set( stream, "thumbnail", "" );
				return;
			}
			set( stream, "thumbnailFallbackTried", true );
			const original = stream.thumbnail;
			const slug = encodeURIComponent( stream.slug );
			for ( const endpoint of [ "info", "livestream" ] ) {
				try {
					const image = await fetchThumbnail( slug, endpoint );
					if ( image && image !== original ) {
						set( stream, "thumbnail", image );
						return;
					}
				} catch ( error ) {
					// Try the next source when a thumbnail endpoint is unavailable.
				}
			}
			set( stream, "thumbnail", "" );
		}
	}
});

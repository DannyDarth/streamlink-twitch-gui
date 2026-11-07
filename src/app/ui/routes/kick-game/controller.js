import KickController from "../kick/controller";
import { set } from "@ember/object";

const imageUrl = value => {
	if ( typeof value === "string" ) { return value; }
	if ( !value || typeof value !== "object" ) { return ""; }
	return value.url || value.src || value.link || value.hd_link || "";
};

export default KickController.extend({
	categoryName: "",
	categorySlug: "",
	actions: {
		thumbnailError( stream ) {
			if ( stream.thumbnailFallbackTried ) {
				set( stream, "thumbnail", "" );
				return;
			}
			set( stream, "thumbnailFallbackTried", true );
			const slug = encodeURIComponent( stream.slug );
			fetch( `https://kick.com/api/v2/channels/${slug}/livestream`,
				{ credentials: "omit" } )
				.then( response => response.ok ? response.json() : null )
				.then( payload => {
					const live = payload && ( payload.data || payload );
					const image = live && imageUrl( live.thumbnail || live.thumbnail_url );
					set( stream, "thumbnail", image && image !== stream.thumbnail ? image : "" );
				})
				.catch( () => set( stream, "thumbnail", "" ) );
		}
	}
});

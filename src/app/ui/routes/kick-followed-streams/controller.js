import Controller from "@ember/controller";
export default Controller.extend({
	loading: true,
	streams: null,
	error: null,
	actions: {
		openBrowser( slug ) {
			require( "nw.gui" ).Shell.openExternal( "https://kick.com/" + slug );
		}
	}
});

import Route from "@ember/routing/route";

const REFRESH_INTERVAL = 60000;

export default Route.extend({
	refreshTimer: null,

	activate() {
		this._super( ...arguments );
		const controller = this.controllerFor( "kickFollowedChannels" );
		controller.refreshChannels();
		this.refreshTimer = setInterval( () => {
			if ( !controller.loading ) {
				controller.refreshChannels();
			}
		}, REFRESH_INTERVAL );
	},

	deactivate() {
		this._super( ...arguments );
		clearInterval( this.refreshTimer );
		this.refreshTimer = null;
	}
});

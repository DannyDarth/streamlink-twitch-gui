function lazyGet( obj, prop, callback ) {
	Object.defineProperty( obj, prop, {
		configurable: true,
		enumerable: true,
		get() {
			const value = callback( obj );

			Object.defineProperty( obj, prop, {
				enumerable: true,
				get() {
					return value;
				}
			});

			return value;
		}
	});
}


function getVersion( config ) {
	// this needs to be executed synchronously, since loading grunt's config can't be deferred
	const { spawnSync } = require( "child_process" );
	const { status, error, stdout, stderr } = spawnSync(
		"git",
		[ "describe", "--tags", "--dirty" ],
		{
			stdio: [ "ignore", "pipe", "pipe" ],
			maxBuffer: 1024,
			timeout: 4000,
			windowsHide: true
		}
	);

	// use a static version string from package.json if git can't be found or if not a git repo
	if ( error || status !== 0 || stderr.toString().length ) {
		// package.version does not have a leading 'v'
		return `v${config.package.version}`;
	}

	const output = stdout.toString().trim();

	// Convert Git's commit-distance suffix to valid semver build metadata first.
	// For example: v2.5.3-4-gabcdef0-dirty -> v2.5.3+4.gabcdef0.dirty
	const normalized = output.replace(
		/-(\\d+-g[a-f0-9]+(-dirty)?)$/,
		( _, suffix ) => `+${suffix.replace( /-/g, "." )}`
	);

	const semver = require( "semver" );
	if ( semver.parse( normalized ) ) {
		return normalized;
	}

	// Forks may contain unrelated tags that cannot describe a semver version.
	// Use the declared package version rather than failing the entire build.
	return `v${config.package.version}`;
}


module.exports = function( config ) {
	lazyGet( config, "version", getVersion );
};

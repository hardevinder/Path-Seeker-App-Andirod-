import org.gradle.api.file.Directory

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

/**
 * ✅ FIX: hypersdkflutter expects client-id(s) in Gradle properties/ext at configuration time.
 * We'll set them on BOTH rootProject and hypersdkflutter project, as BOTH string & list.
 */
gradle.beforeProject {
    // run early for every project creation
    val cid = (rootProject.findProperty("JUSPAY_CLIENT_ID") as String?)?.trim()
        ?.takeIf { it.isNotEmpty() } ?: "hdfcmaster"

    // ✅ Put in ROOT ext (most plugins read from rootProject)
    rootProject.extensions.extraProperties["clientId"] = cid
    rootProject.extensions.extraProperties["client_id"] = cid
    rootProject.extensions.extraProperties["client-id"] = cid

    // Often they want "clientIds" / "client_ids"
    // ✅ String format (most common): "id1,id2"
    rootProject.extensions.extraProperties["clientIds"] = cid
    rootProject.extensions.extraProperties["client_ids"] = cid
    rootProject.extensions.extraProperties["client-ids"] = cid

    // ✅ Also provide list format (some scripts use it)
    rootProject.extensions.extraProperties["clientIdsList"] = listOf(cid)
    rootProject.extensions.extraProperties["client_ids_list"] = listOf(cid)
}

subprojects {
    if (name == "hypersdkflutter") {
        val cid = (rootProject.findProperty("JUSPAY_CLIENT_ID") as String?)?.trim()
            ?.takeIf { it.isNotEmpty() } ?: "hdfcmaster"

        // ✅ Put on hypersdkflutter project ext as well
        extensions.extraProperties["clientId"] = cid
        extensions.extraProperties["client_id"] = cid
        extensions.extraProperties["client-id"] = cid

        // ✅ String format
        extensions.extraProperties["clientIds"] = cid
        extensions.extraProperties["client_ids"] = cid
        extensions.extraProperties["client-ids"] = cid

        // ✅ List format (extra safety)
        extensions.extraProperties["clientIdsList"] = listOf(cid)
        extensions.extraProperties["client_ids_list"] = listOf(cid)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

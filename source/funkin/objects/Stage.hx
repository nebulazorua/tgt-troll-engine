package funkin.objects;

import haxe.Json;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxBasic;
import funkin.Paths;
import funkin.Paths.ContentMetadata;
import funkin.data.Song;
import funkin.scripts.*;

using StringTools;

typedef StageFile =
{
	var directory:String;
	var defaultZoom:Float;

	var boyfriend:Array<Dynamic>;
	var girlfriend:Array<Dynamic>;
	var opponent:Array<Dynamic>;
	@:optional var hide_girlfriend:Bool;

	@:optional var camera_boyfriend:Array<Float>;
	@:optional var camera_opponent:Array<Float>;
	@:optional var camera_girlfriend:Array<Float>;
	@:optional var camera_speed:Null<Float>;

	@:optional var bg_color:Null<String>;

    // title screen vars
	@:optional var camera_stage:Array<Float>; 
    @:optional var title_zoom:Float;

	// caching
	@:optional var preloadStrings:Array<String>;
	@:optional var preload:Array<funkin.data.Cache.AssetPreload>; // incase you would like to add more information, though you shouldnt really need to
}

class Stage extends FlxTypedGroup<FlxBasic>
{
	public var curStage:String = "stage" #if tgt + "1" #end;
	public var stageData:StageFile = {
		directory: "",
		defaultZoom: 0.8,
		boyfriend: [500, 100],
		girlfriend: [0, 100],
		opponent: [-500, 100],
		hide_girlfriend: false,
		camera_boyfriend: [0, 0],
		camera_opponent: [0, 0],
		camera_girlfriend: [0, 0],
		camera_speed: 1
	};
	public var foreground = new FlxTypedGroup<FlxBasic>();

	public var stageScript:FunkinHScript;
	public var spriteMap = new Map<String, FlxBasic>();

	public function new(?stageName:String, ?runScript:Bool = true)
	{
		super();

		if (stageName != null)
			curStage = stageName;
		
		var stageData = StageData.getStageFile(curStage);
		if (stageData != null)
			this.stageData = stageData;
		else
			trace('Failed to load StageData file "$curStage"');

		if (runScript)
			startScript(false);
	}

	var stageBuilt:Bool = false;
	public function startScript(?buildStage = false, ?additionalVars:Map<String, Any>)
	{
		if (stageScript != null)
		{
			trace("Stage script already started!");
			return;
		}

		if (additionalVars == null)
			additionalVars = ["inTitlescreen" => false];
		else if (!additionalVars.exists("inTitlescreen"))
			additionalVars.set("inTitlescreen", false);        

		var baseFile:String = 'stages/$curStage.hscript';
	
		for (file in [#if MODS_ALLOWED Paths.modFolders(baseFile), #end Paths.getPreloadPath(baseFile)])
		{
			if (!Paths.exists(file))
				continue;
		
			stageScript = FunkinHScript.fromFile(file, file, additionalVars);

			// define variables lolol
			stageScript.set("stage", this); // for backwards compat lol
			stageScript.set("add", add);
			stageScript.set("remove", remove);
			stageScript.set("insert", insert);
			stageScript.set("this", this);
			stageScript.set("foreground", foreground);
			
			if (buildStage){
				stageScript.call("onLoad", [this, foreground]);
				stageBuilt = true;
			}

			break;
		}
	}

	public function buildStage()
	{
		if (!stageBuilt){
			// In case you want to hardcode your stages
			/* 
			switch (curStage)
			{
				case "example":
					var ground = new FlxSprite(-2048, -100);
					ground.makeGraphic(4096, 1280, 0xFFEAEAEA);
					this.add(ground);

					var block1 = new FlxSprite(-1750, -250);
					block1.makeGraphic(512, 512, 0xFF888888);
					block1.offset.set(256, 256);
					block1.scrollFactor.set(1.6, 1.2);
					foreground.add(block1);

					var block2 = new FlxSprite(1000, -250);
					block2.makeGraphic(512, 512, 0xFF888888);
					block2.offset.set(256, 256);
					block2.scrollFactor.set(1.6, 1.2);
					foreground.add(block2);
			}
			*/
			
			if (stageScript != null){
				if (stageScript is FunkinLua)
					stageScript.call("onCreate", []);
				else
					stageScript.call("onLoad", [this, foreground]);
			}

			stageBuilt = true;
		} 

		return this;
	}

	override function destroy()
	{
		if (stageScript != null){
			stageScript.call("onDestroy");
			stageScript.stop();
			stageScript = null;
		}
		
		super.destroy();
	}

	override function toString(){
		return 'Stage: "$curStage"';
	}

	/**
		Return an array with the names in the stageList file(s).
	**/ 
	public static function getTitleStages(modsOnly = false):Array<String>{
	
		var daList:Array<String> = [];
		#if MODS_ALLOWED
		if (modsOnly){
			var modPath:String = Paths.modFolders('data/stageList.txt');
			if (Paths.exists(modPath))
			{
				var modsList = Paths.getContent(modPath);
				if (modsList != null && modsList.trim().length > 0)
                    for (shit in modsList.split("\n"))
                        daList.push(shit.trim().replace("\n", ""));
			}

        }else{
			var modsList = Paths.getText('data/stageList.txt', false);
			if (modsList != null && modsList.trim().length > 0)
				for (shit in modsList.split("\n"))
					daList.push(shit.trim().replace("\n", ""));
        }


		 
		var path = Paths.modFolders("metadata.json");
		var rawJson:Null<String> = Paths.getContent(path);

		if (rawJson != null && rawJson.length > 0)
		{
			var daJson:Dynamic = Json.parse(rawJson);
			if (Reflect.field(daJson, "titleStages") != null)
			{
				var data:ContentMetadata = cast daJson;
				for (stage in data.titleStages)
				{
					daList.push(stage.trim().replace("\n",""));
				}
			}
		}

		#end
		return daList;
	}

	/**
		Returns an array with every stage in the stages folder(s).
	**/
	#if !sys
	private static var _stageCache:Null<Array<String>> = null;
	#end
	public static function getAllStages(modsOnly = false):Array<String>
	{
		#if !sys
		if (_stageCache != null)
			return _stageCache;

		var stages:Array<String> = _stageCache = [];
		#else
		var stages:Array<String> = [];
		#end

		function readFileNameAndPush(fileName: String){
			if (fileName==null)return;
            
			if (!fileName.endsWith(".json")) return;

			var name = fileName.substr(0, fileName.length - 5);
			if(!stages.contains(name))stages.push(name);
		}
		
		for (folderPath in Paths.getFolders("stages", true)){
			if (Paths.isDirectory(folderPath)){
				Paths.iterateDirectory(folderPath, readFileNameAndPush);
			}
		}

		if (!modsOnly){
			var folderPath = Paths.getPath('stages/');
			if (Paths.isDirectory(folderPath)){
				Paths.iterateDirectory(folderPath, readFileNameAndPush);
			}
		}

		return stages;
	}

	/*
	//// stage -> modDirectory
	public static function getStageMap():Map<String, String>
	{
		var directories:Array<String> = [
			#if MODS_ALLOWED
			Paths.mods(Paths.currentModDirectory + '/stages/'),
			Paths.mods('stages/'),
			#end
			Paths.getPreloadPath('stages/')
		];

		var theMap:Map<String, String> = new Map();

		return theMap;
	}
	*/
}

class StageData {
	public static var forceNextDirectory:String = null;

	public static function loadDirectory(SONG:SwagSong) {
		var stage:String = 'stage';

		if (SONG.stage != null)
			stage = SONG.stage;

		var stageFile:StageFile = getStageFile(stage);

		// preventing crashes
		forceNextDirectory = stageFile == null ? '' : stageFile.directory;
	}
	
	public static function getStageFile(stageName:String):Null<StageFile> 
	{
		return Paths.json('stages/$stageName.json', false);
	}
}

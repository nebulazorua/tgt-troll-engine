package funkin.data;

import funkin.Paths.ContentMetadata;
import haxe.io.Path;

typedef WeekMetadata = {
	/**
		Name of the week. 
	**/
	var name:String;
	
	/**
		Any week that isn't 'main' shouldn't be displayed in the story menus. 
	**/
	var category:String;

	/**
		Incase you want a main week to appear in a seperate freeplay category
	**/
	@:optional var freeplayCategory:String;
	
	/**
		Not implemented!
		In case of being a string it would've been checked from a Map from your save file
		as FlxG.save.data.unlocks.get(unlockCondition) maybe
	**/
	var unlockCondition:Any;
	
	/**
		Song names of this week.
	**/
	var songs:Array<String>;
	
	/**
		Name of the content folder containing this week
	**/
    var ?directory:String;
}

class WeekData
{
	// public static var chaptersMap:Map<String, WeekMetadata> = new Map();
	public static var chaptersList:Array<WeekMetadata> = [];
	public static var curChapter:Null<WeekMetadata> = null;

	public static var weekCompleted(get, null):Map<String, Bool>;
	@:noCompletion static function get_weekCompleted() return Highscore.weekCompleted;

	public static function reloadChapterFiles():Array<WeekMetadata>
	{
		var list:Array<WeekMetadata> = [];

		#if MODS_ALLOWED
		inline function pushChapter(chapter, mod){
			chapter.directory = mod;
			list.push(chapter);
		}

		for (mod in Paths.getModDirectories()){
			Paths.currentModDirectory = mod;

			var jsonPath:String = Paths.modFolders("metadata.json", false);
			var daJson:Null<Dynamic> = Paths.getJson(jsonPath);

			if (daJson != null)
            {
				if (Reflect.field(daJson, "weeks") == null)
				{
					// tgt compat 
					var chapters:Dynamic = Reflect.field(daJson, "chapters");
					if (chapters != null){ 	
						Reflect.setField(daJson, "weeks", chapters);
						Reflect.deleteField(daJson, "chapters");
					}else // old tgt
						daJson = {weeks: [daJson]};
				}

				var data:ContentMetadata = cast daJson;
				for (week in data.weeks)
					pushChapter(week, mod);
			}

			#if PE_MOD_COMPATIBILITY
			var modWeeksPath:String = Paths.modFolders("weeks", false);
			var modWeekList:Array<String> = CoolUtil.coolTextFile('$modWeeksPath/weekList.txt');
			var modWeeksPushed:Array<String> = [];

			for (weekName in modWeekList){
				var data = portPsychWeek(Paths.getJson('${modWeeksPath}/${weekName}.json'), weekName);
				if (data != null){
					pushChapter(data, mod);
					modWeeksPushed.push(weekName);
				}
			}

			Paths.iterateDirectory(modWeeksPath, (fileName:String)->{
				var path = new Path('$modWeeksPath/$fileName');
				var weekName:String = path.file;

				if (path.ext != "json" || modWeeksPushed.contains(weekName))
					return;

				var data = portPsychWeek(Paths.getJson('$modWeeksPath/$fileName'), weekName);
				if (data != null){
					pushChapter(data, mod);
					modWeeksPushed.push(weekName); // what if the same name was written more than once :o
				}
			});
			#end
		}
		Paths.currentModDirectory = '';
        #end

		chaptersList = list;

		return list;
	}

	#if PE_MOD_COMPATIBILITY
	static function portPsychWeek(json:Dynamic, name):Null<WeekMetadata>
	{
		if (json == null)
			return null;

		var vChapter:WeekMetadata = {
			name: name,
			songs: [],
			category: 'psychengine', //'main',
			// freeplayCategory: '$mod - $name',
			unlockCondition: true,
			//directory: mod
		};

		if (json.hideStoryMode == true)
			vChapter.category = "hidden";

		var psychSongs:Null<Array<Dynamic>> = json.songs;
		if (psychSongs != null)
		{
			var songs:Array<String> = vChapter.songs;
			for (songData in psychSongs)
				songs.push(songData[0]);
		}

		vChapter.unlockCondition = json.startUnlocked != false; /* || (json.weekBefore!=null && weekCompleted.get(json.weekBefore)); */

		return vChapter;
	}
	#end
}
@license{
  Copyright (c) 2009-2015 CWI
  All rights reserved. This program and the accompanying materials
  are made available under the terms of the Eclipse Public License v1.0
  which accompanies this distribution, and is available at
  http://www.eclipse.org/legal/epl-v10.html
}
@contributor{Atze van der Ploeg - ploeg@cwi.nl - CWI}
module tetris::Tetris

import IO;
import tetris::TetrisState;
import tetris::PlayField;
import tetris::Tetromino;
import vis::Figure;
import vis::Render;
import vis::KeySym;
import util::Maybe;
import List;
import util::Math;
import IO;
import ValueIO;
import DateTime;

data HighScore  = highScore(str name,int score);
alias Highscores = list[HighScore];
 // does not work on windows
loc highscoresFile = |home:///rascaltetrishighscores.bin|;
int nrHighscores = 6;
int minSpinTime = 250; // milliseconds
int nrNext = 4;
int minDropTime = 15;

str pauseText = 
"\<Paused!\>
				
Tetris for Rascal!!

Original Tetris by Alexey Pajitnov
Rascal version by Atze van der Ploeg

Move mouse over game to start!

Keys: 
Left/Right: arrows left/right
Rotate(counterclockwise): z
Rotate(clockwise): x
Down : arrow down
Drop : Space
Swap : a
Restart: F1";

// This is actually standardized :) see wikipedia
list[Color] blockColors = 
	[ color(c) | c <- ["cyan","blue","orange","yellow","green","purple","red"]];
Color predictedColor(Color blockColor) = 
	interpolateColor(blockColor,color("black"),0.55);
list[Color] predictedColors = [ predictedColor(b) | b <- blockColors];

Highscores readHighscores(){
	if(exists(highscoresFile)){
		return readBinaryValueFile(#Highscores, highscoresFile);
	} else {
		return [highScore("No one",0)| _ <- [1 .. nrHighscores+1]];
	}
}
void writeHighscores(Highscores highscores) { 
	try{
		writeBinaryValueFile(highscoresFile, highscores);
	} catch e : {
		println("Error writing highscores!");
		iprintln(e);
	}
}
bool newHighScore(Highscores highscores,int score) = 
	score >= highscores[nrHighscores-1].score;
	
bool highScoreOrd(HighScore l,HighScore r) = l.score > r.score; 
bool isValidName(str name) = name != "";
Highscores addHighScore(Highscores s, HighScore n) {
	 s = sort([n] + s, highScoreOrd);
	 writeHighscores(s);
	 return s;
}

int timeTillDrop(TetrisState state) = max(minDropTime, 1500 - state.level*120);

Color getColor(PlayFieldState s){
	switch(s){
		case prediction(i) : return predictedColors[i];
		case block(i)      : return blockColors[i];
		default            : return color("black");
	}
}

Maybe[Action] keyToAction(keyArrowDown()) = just(normalAction(acDown()));
Maybe[Action] keyToAction(keyArrowLeft())    = just(spinAction(acLeft()));
Maybe[Action] keyToAction(keyArrowRight())   = just(spinAction(acRight()));
Maybe[Action] keyToAction(keyPrintable("z")) = just(spinAction(acRotateCCW()));
Maybe[Action] keyToAction(keyArrowUp())      = just(spinAction(acRotateCW()));
Maybe[Action] keyToAction(keyPrintable("x")) = just(spinAction(acRotateCW()));
Maybe[Action] keyToAction(keyPrintable("a")) = just(normalAction(acSwap()));
Maybe[Action] keyToAction(keyEnter())        = just(normalAction(acDrop()));
Maybe[Action] keyToAction(keyPrintable(" ")) = just(normalAction(acDrop()));

default Maybe[Action] keyToAction(KeySym _) = nothing();

Figure tetrominoFigure(int tetromino){
	<blocks,nrR,nrC> = getCanconicalRep(tetromino);
	Color getColor(int r, int c) = 
		<r,c> in blocks ? blockColors[tetromino] : color("black");
	elems = [[box(fillColor(getColor(r,c))) | c <- [0..nrC]] | r <- [0..nrR]];

	hshrinks = toReal(nrC) / toReal(maxTetrominoWidth);
	vshrinks = toReal(nrR) / toReal(maxTetrominoHeight);
	as = toReal(maxTetrominoWidth) / toReal(maxTetrominoHeight);
	return space(grid(elems,shrink(hshrinks,vshrinks)),aspectRatio(as));
}


list[Figure] allTetrominoFigures= [tetrominoFigure(t) | t <- index(tetrominos)];

public Figure tetris(){
	state = initialState();
	paused = true;
	justPerfomedAction = true;
	dropped = false;
	highscores = readHighscores();
	highscoreEntered = false;
	
	void enterHighscore(str name){
		if(!highscoreEntered) {
			highscores = addHighScore(highscores,highScore(name,state.score));
			highscoreEntered = true;
		}
	}
	
	void restart(){
		state = initialState();
		justPerfomedAction = false;
		dropped = false;
		highscoreEntered = false;
	}
	
	bool keyDown(KeySym key, map[KeyModifier,bool] _){
		if (paused) return true;
		currentAction = keyToAction(key);
		if (!state.gameOver && just(action) := currentAction) {
			oldSpin = state.spinCounter;
			state = performAction(state, action);
			justPerfomedAction = oldSpin != state.spinCounter;
			dropped = normalAction(acDrop()) == action;
			return true;
		 }
		 if(keyF1() := key) {
		 	restart();
		 	return true;
		 }
		 return false;
	}
	
	void pause() { paused = true;  }
	void resume(){ paused = false; }
	bool showPause() = paused && !state.gameOver; 
	bool isGameOver() = state.gameOver;
	bool nothingStored() = nothing() == state.stored;;
	void handleTimer(){ state = performAction(state, normalAction(acDown())); }
	bool mayEnterHighscore() = 
		!highscoreEntered && newHighScore(highscores,state.score);

	TimerAction initTimer(TimerInfo info){
		if(state.gameOver){ 
			return stop(); 
		} else if(dropped){   // allow a little time to move a tetromino after
			dropped = false; // drop
			justPerfomedAction = false;
			return TimerAction::restart(minSpinTime);
		} else if(justPerfomedAction){
			/* if an action was performed then the remaining time till
			   gravity (down) should stay the same
			   however if the remaining time < minSpinTime
			   then we allow a little extra time to manouver
			   this is the same behaviour as can be seen in for
			   example tetris DS */
			justPerfomedAction = false;
			switch(info) {
				case stopped(timeElapsed) : 
					return TimerAction::restart(
							max(minSpinTime,timeTillDrop(state) - timeElapsed));
				case running(timeLeft) : {
					if(timeLeft > minSpinTime){
						return noChange();
					} else {
						return TimerAction::restart(minSpinTime);
					}
				}
				default:
				return noChange();
			}
		} else if(stopped(timeElapsed) := info){
			return TimerAction::restart(timeTillDrop(state)- timeElapsed);
		} else {
			return noChange();
		}
	}
	
	Figure playFieldElem(int r,int c) = 
		box(fillColor(Color (){ return getColor(getPF(state.screen,<r,c>)); }));
		
	playFieldElems = [[playFieldElem(r,c) | c <- colIndexes(state.screen)] | r <- rowIndexes(state.screen)];
	playFieldAS = toReal(nrCols(state.screen)) / toReal(nrRows(state.screen));
	playFieldFig =  grid(playFieldElems, aspectRatio(playFieldAS)
						,timer(initTimer,handleTimer));
	
	Figure tetrominoFig(int () which) = 
		box(fswitch(which, allTetrominoFigures),grow(1.1),fillColor("black"));
	
	storedTetrominoFig = 
		boolFig(nothingStored,
				text("Nothing"),
				tetrominoFig(int () { return state.stored.val; }));
	storedFig = vcat([text("stored:",bottom()),
					  box(storedTetrominoFig,fillColor("black"))]);
					  
	Figure highScoreFig(int i) = 
		hcat([text(str () { return highscores[i].name; },left()), 
			  text(str () { return "<highscores[i].score>"; },right())]);
	highScoresFig = box(
		vcat([highScoreFig(i) | i <- [0..nrHighscores]],vgrow(1.03)),
		fillColor("black"),grow(1.1));
		
	Color() spinColor(int i) =
		Color() { 
		 	return  (i  >= state.spinCounter) ? color("red") : color("black"); 
		 };
	spinFig = box(
		vcat([box(fillColor(spinColor(i)))
		    | i <- [0..state.maxSpinCounter]]),
		fillColor("black"),aspectRatio(0.5)); 	
		
	leftBarFig = vcat([storedFig,
					   text(str () { return "Level: <state.level>";}),
					   text(str () { return "Score: <state.score>";}),
					   text("Spin Left:"),
					   spinFig,
					   text("High scores:"),
					   highScoresFig],hshrink(0.25),vgrow(1.05));
	
	Figure nextFig(int i) = tetrominoFig(int () { return state.next[i]; });
	nextsFig = vcat([ nextFig(i) | i <- [0..nrNext]],vgrow(1.2));
	rightBarFig = vcat([text("next:",bottom()), nextsFig],
					   hshrink(0.15));
					   
	enterHighScoreFig = 
		vcat([text("Enter your name for HIGHSCORE!"),
			 textfield("",enterHighscore, isValidName,
			 		fillColor("white"),fontColor("black"),vresizable(false))
		],vgrow(1.03));
	gameOverFig =  
		box(vcat([text("GAME OVER!",fontSize(25)),
				  ifFig(mayEnterHighscore, enterHighScoreFig),
				  text("press F1 to restart")],
			vgrow(1.2),vshrink(0.5))
		,fillColor(color("darkblue",0.6)),lineColor(color("darkblue",0.6)));
		
	gameFig = hcat([leftBarFig, playFieldFig, rightBarFig]);
	mainFig  = overlay([gameFig,ifFig(isGameOver,gameOverFig)]);
	
	pauseFig = box(text(pauseText),fillColor("black"),shrink(0.9));

	return box(vcat([text("Rascal Tetris!",fontSize(20),top()),
					boolFig(showPause, pauseFig, mainFig)],vgrow(1.02)),
			onMouseEnter(resume),onMouseExit(pause),onKeyDown(keyDown),
			std(fontColor("white")),std(fillColor("darkblue")),
			aspectRatio(18.0/20.0),grow(1.03)); 
}
	 
public void playTetris() = render(tetris());
	

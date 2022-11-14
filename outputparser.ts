const fs = require("fs");
import axios from "axios";




const config = {
    headers: {
        'Content-Type': 'text/plain'
    }
};

const url = "https://github-tests-to-telegram-bot.1epl1di4e824g.eu-west-2.cs.amazonlightsail.com/";


function escapeString(string: any){
    let escapeables = ["*", "_", '{', '}', '[', ']', '<', '>', '(', ')', '#', '+', '-', '.', '!', '|', '='];

    escapeables.forEach(function(escapable){
        const regex = new RegExp('\\' + escapable, "gi");
        string = string.replace(regex, "\\" + escapable);
    }); 
    return string;
}



function coverage(){
    var retn: string = "";
    retn += "\`\`\`\nCOVERAGE";
    retn += "\n___________________________________________________________________";
    const rgx = /src\/.*.sol *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\)/gi;
    const findNull = /\0/g;
    const filename = "coverage_output.txt";

    const cov = fs.readFileSync(filename).toString();
    var withoutNulls = cov.replace(findNull, "");

    const matches = withoutNulls.match(rgx);

    const coverage = {
        lines: [0, 0],
        statements: [0, 0],
        branches: [0, 0],
        functions: [0, 0],
    }

    for (const contract of matches) {
        retn += "\n" + contract;
        const rgx2 = /src\/.*.sol *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\) *\| \d{1,3}.\d{1,3}% \((\d+\/\d+)\)/gi;

        const contractCoverage: any = rgx2.exec(contract);

        const linesCoverage = parseCoverage(contractCoverage[1]);
        coverage.lines = addCoverage(coverage.lines, linesCoverage);

        const statementsCoverage = parseCoverage(contractCoverage[2]);
        coverage.statements = addCoverage(coverage.statements, statementsCoverage);

        const branchesCoverage = parseCoverage(contractCoverage[3]);
        coverage.branches = addCoverage(coverage.branches, branchesCoverage);

        const functionsCoverage = parseCoverage(contractCoverage[4]);
        coverage.functions = addCoverage(coverage.functions, functionsCoverage);
    }

    function printCoverage() {
    return `
    lines: ${((coverage.lines[0] / coverage.lines[1]) * 100).toFixed(2)}% (${coverage.lines[0]}/${coverage.lines[1]})
    lines: ${((coverage.statements[0] / coverage.statements[1]) * 100).toFixed(2)}% (${coverage.statements[0]}/${coverage.statements[1]})
    branches: ${((coverage.branches[0] / coverage.branches[1]) * 100).toFixed(2)}% (${coverage.branches[0]}/${coverage.branches[1]})
    functions: ${((coverage.functions[0] / coverage.functions[1]) * 100).toFixed(2)}% (${coverage.functions[0]}/${coverage.functions[1]})
    `
    }

    retn += "\n" + printCoverage();

    function parseCoverage(coverageString: any) {
        const covrg = coverageString.split("/");

        return [parseInt(covrg[0]), parseInt(covrg[1])];
    }

    function addCoverage(covArray: any, newCov: any) {
        return [covArray[0] + newCov[0], covArray[1] + newCov[1]];
    }
    retn += "\n___________________________________________________________________\`\`\`";
    
    return retn;
}

function sizes() {
    var retn: string = "";
    retn += "\`\`\`\nSIZES";
    retn += "\n___________________________________________________________________";
    const re = /([a-zA-Z0-9.() ])+/g;
    const findNull = /\0/g;
    const findSpace = / /g;
    const filename = "sizes_output.txt";

    var text = fs.readFileSync(filename, 'utf-8');

    const arr = text.split(/\r?\n/);

    class Entry {
        Contract: string;
        Size_kB: string;
        Margin_kB: string;
        constructor(name: string, size: string, margin: string){
            this.Contract = name;
            this.Size_kB = size;
            this.Margin_kB = margin;
        }
    }

    var table = [];
    for(var i = 0; i < arr.length; i++){
        var a = arr[i].search(/[╭│]/)
        if( a != -1){
            var withoutNulls = arr[i].replace(findNull, "");
            var withoutSpaces = withoutNulls.replace(findSpace, "");
            const match = [...withoutSpaces.matchAll(re)];
            if(match){
                try{
                    if(match[0][0] != "Contract"){ // table header
                        retn += (match[0][0], match[1][0], match[2][0] + "\n");
                        table.push(new Entry(match[0][0], match[1][0], match[2][0]));
                    }
                }
                catch(e){}
            }
        }
    }


    retn += ("\n___________________________________________________________________\`\`\`");
    return retn;
}


function test() {
    var retn: string = "";
    retn += ("\`\`\`\nTESTS");
    retn += ("\n___________________________________________________________________");

    const filename = "test_output.txt";
    const findNull = /\0/g;
    var text = fs.readFileSync(filename, 'utf-8');
    var withoutNulls = text.replace(findNull, "");
    const arr = withoutNulls.split(/\r?\n/);

    var json = JSON.parse(arr[1]);
    
    for(var i in json) {
        retn += (`\n${i} - duration ${json[i].duration.secs + json[i].duration.nanos / 1000000000}s`);
        for(var j in json[i].test_results){
            retn += (`\n${j}: ${json[i].test_results[j].success}`)
        }
        retn += "\n";
    }
    retn += ("\n___________________________________________________________________\`\`\`");
    return retn;
}


axios.post(url, coverage(), config);
axios.post(url, escapeString(sizes()), config);
axios.post(url, escapeString(test()), config);

package iptables;

import iptables.analyser.types.*;
import tom.library.sl.*; 
import java.util.*;
import java.io.*;


public class Analyser {
	public static class InteractiveNeededException extends RuntimeException { }

	%include {iptables/analyser/Analyser.tom}
	%include {sl.tom}

	public static final int 
		NOT_COMPARABLE = Integer.MAX_VALUE,
		INCLUDEDEQ = -1, INCLUDEDDIF = -2,
		EQUALSEQ = 0, EQUALSDIF = 8,
		INCLUDESEQ = 1, INCLUDESDIF = 2;

	public static void printError(String errtype, Rule r1, String errmsg,
		Rule r2) {
		System.err.println("error[" + errtype + "]: " + `r1 + " <" + 
			errmsg + "> " + `r2 + "\n");
	}

	public static void printWarning(String errtype, Rule r1, String errmsg,
		Rule r2) {
		System.err.println("warning[" + errtype + "]: " + `r1 + " <"
			+ errmsg + "> " + `r2 + "\n");
	}

	public Rule getDisplayRuleChoice(String msg, Rule r1, Rule r2) {
		System.out.print("\n[1] " + `r1 + "\n[2] " + `r2 + "\n" + msg 
			+ " [1/2] ? ");
		BufferedReader input = 
			new BufferedReader(new InputStreamReader(System.in));
	
		int i = 1;
		try {
			i = Integer.parseInt(input.readLine());
		} catch (Exception e) {}
		System.out.println("");

		if (i == 1)
			return `r2;
		else
			return `r1;
	}


	public static Rules checkIntegrity(Rules rs) {
		try {
			rs = `OutermostId(checkIntegrityStrategy()).visit(rs);
		} catch (VisitFailure vf) { }
		return rs;
	}


	%strategy checkIntegrityStrategy() extends Identity() { 
		visit Rules {
			Rules(
				X*,
				r1@Rule(_,_,_,_,_,_,_,_,_,_),
				Y*,
				r2@Rule(_,_,_,_,_,_,_,_,_,_),
				Z*
			) -> {
				Rule del = null;

				/* check redundancies */
				del = checkRedundancy(`r1,`r2);
				/* check correlations */
				checkCorrelation(`r1,`r2);

				try {
					/* check shadowing */
					checkShadowing(`r1,`r2);
					/* check generalization */
					checkGeneralization(`r1,`r2);
					
				} catch (InteractiveNeededException ine) {
					del = (new Analyser()).getDisplayRuleChoice(
						"Which rule do you want to delete"
						,`r1,`r2);
				}

				if (del != null) {
					if (del == `r1)
						return `Rules(X*,r1,Y*,Z*);
					else 
						return `Rules(X*,Y*,r2,Z*);
				}
			}
		}
	}

	public static Rule checkShadowing(Rule r1, Rule r2) 
					throws InteractiveNeededException {
		%match(r1,r2) {
				Rule(_,_,_,_,_,_,_,_,_,_),
				Rule(_,_,_,_,_,_,_,_,_,_)
			 -> {
				int i = isInclude(`r1,`r2);
				if (i == INCLUDEDDIF) {
					printError("shadowing",`r1,
						"shadows",`r2);
					throw new InteractiveNeededException();
				} else if (i == EQUALSDIF) {
					printError("shadowing",`r1,
						"in conflict with",`r2);
					throw new InteractiveNeededException();
				}
			}
		}
		return null;
	}

	/* returns englobing rule */
	public static Rule checkRedundancy(Rule r1, Rule r2) {
		%match(r1,r2) {
				Rule(_,_,_,_,_,_,_,_,_,_),
				Rule(_,_,_,_,_,_,_,_,_,_)
			 -> {
				int i = isInclude(`r1,`r2);
				if (i == INCLUDESEQ) {
					printWarning("redundancy",`r2,
						"included in",`r1);
					return `r1;
				} else if (i == INCLUDEDEQ) {
					printWarning("redundancy",`r1,
						"included in",`r2);
					return `r2;
				} else if (i == EQUALSEQ) {
					printWarning("redundancy",`r1,
						"equivalent to",`r2);
					return `r1;
				}
			}
		}
		return null;
	}

	public static Rule checkGeneralization(Rule r1, Rule r2)
					throws InteractiveNeededException {
		%match(r1,r2) {
				Rule(_,_,_,_,_,_,_,_,_,_),
				Rule(_,_,_,_,_,_,_,_,_,_)
			 -> {
				int i = isInclude(`r1,`r2);
				if (i == INCLUDESDIF) {
					printWarning("generalization",`r1,
						"generalized by",`r2);
					throw new InteractiveNeededException();
				}
			}
		}
		return null;
	}

	public static Rule checkCorrelation(Rule r1, Rule r2) {
		%match(r1,r2) {
				Rule(_,_,_,_,_,_,_,_,_,_),
				Rule(_,_,_,_,_,_,_,_,_,_)
			 -> {
				int i = isInclude(`r1,`r2);
				if (i == INCLUDEDDIF)  {
					printWarning("correlation",`r1,
						"correlated to",`r2);
				}
			}
		}
		return null;
	}

	/* 	returns:
			0 if Rules are equals, 
			1 if r2 is included in r1,
			-1 if r1 include in r2
			NOT_COMPARABLE if the 2 rules are not comparable
	*/
	private static int isInclude(Rule r1, Rule r2) {
		%match(r1,r2) {
			Rule(action1,iface,proto,target,srcaddr1,dstaddr1,srcport,dstport,opts,_),
			Rule(action2,iface,proto,target,srcaddr2,dstaddr2,srcport,dstport,opts,_) -> {
				int i1 = AddressTools.isInclude(`srcaddr1,`srcaddr2),
					i2 = AddressTools.isInclude(`dstaddr1,`dstaddr2),ret = Integer.MAX_VALUE;
				if ((i1 != NOT_COMPARABLE) && (i2 != NOT_COMPARABLE)) {
					if (i1 == 0) {
						ret = i2;
					} else if (i2 == 0) {
						ret = i1;
					} else {
						if ((i1 > 0) && (i2 > 0))
							ret = INCLUDESEQ;
						else if ((i1 < 0) && (i2 < 0))
							ret = INCLUDEDEQ;
					}
					if (`action1 == `action2)
						return ret;
					else
						return (ret == EQUALSEQ ? 
							EQUALSDIF : ret * 2);
					
				}
			}
		}
		return NOT_COMPARABLE;
	}
}
